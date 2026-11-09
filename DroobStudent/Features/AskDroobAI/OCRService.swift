import Foundation
import Vision
import UIKit
import PDFKit

/// On-device OCR using Apple Vision framework.
/// Completely free, no API key needed, supports Arabic + English.
struct OCRService {

    /// Extract text from a UIImage using Apple Vision OCR.
    /// Returns recognized text in the image's natural reading order.
    static func extractText(from image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(.failure(OCRError.invalidImage))
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.success(""))
                return
            }

            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }

            let fullText = recognizedStrings.joined(separator: "\n")
            completion(.success(fullText))
        }

        // Support both Arabic and English
        request.recognitionLanguages = ["ar", "en"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            completion(.failure(error))
        }
    }

    /// Async version for modern concurrency.
    @available(iOS 15.0, *)
    static func extractText(from image: UIImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            extractText(from: image) { result in
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    enum OCRError: LocalizedError {
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Could not process the image"
            }
        }
    }
}

// MARK: - Worksheet intake
//
// Turns a picked PDF or image into the plain text of a whole homework sheet,
// then — when the model is unreachable or unhelpful — into a list of separate
// questions using nothing but pattern matching.
//
// Lives in OCRService.swift rather than its own file on purpose: the Xcode
// project has no filesystem-synchronized group, so a new .swift file on disk
// is not compiled until it is registered in project.pbxproj by hand, and a
// missing registration fails silently at runtime rather than at build time.
//
// Everything here is a `nonisolated` static on a caseless enum, so an `await`
// from the @MainActor view model runs it on the cooperative pool: a ten-page
// rasterise-and-OCR pass is 15–30 seconds of work and must never sit on the
// main thread.
enum WorksheetIntake {

    // MARK: Caps — identical values on iOS and Android

    static let maxFileBytes = 20 * 1024 * 1024
    static let maxPages = 10
    static let maxQuestions = 40
    /// Below this much text on a page we assume the PDF page is a scan rather
    /// than born-digital and rasterise it for OCR. A page of real text clears
    /// 40 characters trivially; a scanned page usually yields 0 or a stray
    /// header the producing tool embedded.
    static let minPageTextChars = 40
    static let minTotalTextChars = 20
    static let minQuestionChars = 4

    // MARK: Vision reading budget — identical values on iOS and Android
    //
    // 1536 is exactly 2 × 768, and 768 is Gemini's tile size: an A4 page
    // clamped to 1536 on its longest side is 1085 × 1536, which lands in
    // 2 × 2 = 4 tiles = 1,032 image tokens. 1600 px would be 6 tiles for a 4%
    // resolution gain. Clamping the *longest* side bounds the tile count for
    // any page shape, so no page can ever cost more than 4 tiles.
    //
    // 1536 px across A4 is ~131 DPI, which is above the ~1500 px floor where
    // Vision starts dropping small print — and that matters because the same
    // raster is the OCR fallback for that page. One render serves both readers.
    static let visionLongestSide: CGFloat = 1536
    /// Last rung of the re-encode ladder, for a page that will not fit the byte
    /// cap at any quality.
    static let visionSmallLongestSide: CGFloat = 1152
    static let visionJPEGQuality: CGFloat = 0.75
    /// Hard cap per encoded page. 400 KB of JPEG is 533 KB of base64, so the
    /// whole request body stays around 550 KB — 2.7% of Gemini's 20 MB inline
    /// ceiling, and never enough in flight to matter on a phone connection.
    static let visionMaxJPEGBytes = 400 * 1024

    struct Extraction {
        let text: String
        /// True when the file had more than `maxPages` pages. Not an error —
        /// the first `maxPages` are processed and the student is told.
        let pageCapHit: Bool
    }

    enum IntakeError: Error {
        case tooLarge
        case encrypted
        case unreadable
        case noText
    }

    // MARK: - Extract

    /// PDFKit first, Vision second, per page.
    ///
    /// Born-digital worksheets carry a real text layer, which is both faster
    /// and far more accurate than OCR — especially for Arabic and for
    /// mathematical symbols. Scanned worksheets carry none, so each page that
    /// comes back empty is rendered and passed through the existing Vision
    /// pipeline.
    static func extract(pdfData: Data) async throws -> Extraction {
        guard let doc = PDFDocument(data: pdfData) else { throw IntakeError.unreadable }

        // `isLocked`, not `isEncrypted`: a PDF that merely forbids printing is
        // encrypted but perfectly readable, and refusing it would reject a
        // large share of school-issued worksheets. `isLocked` is the flag that
        // actually means "needs a password we do not have".
        if doc.isLocked { throw IntakeError.encrypted }

        let pageCount = doc.pageCount
        let count = min(pageCount, maxPages)
        let pageCapHit = pageCount > maxPages

        var pageTexts: [String] = []
        for index in 0..<count {
            if Task.isCancelled { break }
            guard let page = doc.page(at: index) else { continue }

            let native = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if native.count >= minPageTextChars {
                pageTexts.append(native)
                continue
            }

            guard let image = rasterise(page: page) else {
                if !native.isEmpty { pageTexts.append(native) }
                continue
            }
            let recognised = (try? await OCRService.extractText(from: image)) ?? ""
            let trimmed = recognised.trimmingCharacters(in: .whitespacesAndNewlines)
            let best = trimmed.count >= native.count ? trimmed : native
            if !best.isEmpty { pageTexts.append(best) }
        }

        let joined = pageTexts
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard joined.count >= minTotalTextChars else { throw IntakeError.noText }
        return Extraction(text: joined, pageCapHit: pageCapHit)
    }

    /// A photographed worksheet — one "page", straight through Vision.
    static func extract(image: UIImage) async throws -> Extraction {
        let recognised = try await OCRService.extractText(from: image)
        let trimmed = recognised.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minTotalTextChars else { throw IntakeError.noText }
        return Extraction(text: trimmed, pageCapHit: false)
    }

    /// Renders one PDF page into a bitmap Vision can read.
    ///
    /// The 2600 px longest-side clamp is the whole trick: below roughly 1500 px
    /// Vision starts dropping small print, and above 2600 px accuracy stops
    /// improving while the bitmap cost keeps climbing — ten pages at full
    /// Retina scale is a memory spike for no gain.
    ///
    /// `longestSide` defaults to the OCR clamp. The vision reader passes 1536
    /// instead (see `visionLongestSide`), and the page it gets back is the same
    /// bitmap the OCR fallback for that page uses, so no page is rendered twice.
    private static func rasterise(page: PDFPage, longestSide: CGFloat = 2600) -> UIImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 1, box.height > 1 else { return nil }

        let scale = min(2.0, longestSide / max(box.width, box.height))
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        guard size.width >= 1, size.height >= 1 else { return nil }

        // `size` is already in the pixels we want, so the renderer must not
        // multiply it again. `UIGraphicsImageRendererFormat.default()` carries
        // the main screen's scale, which on a 3x device would turn a clamped
        // 2600 px page into a 7800 px, ~240 MB bitmap — nine times the
        // allocation the clamp exists to prevent, handed whole to Vision on top
        // of its own working buffers. scale = 1 makes the bitmap exactly
        // `size` pixels, matching Android's `Bitmap.createBitmap(w, h)`.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            // PDF pages are transparent; OCR of white-on-transparent is
            // nothing at all, so paint the sheet first.
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // PDF's origin is bottom-left, UIKit's is top-left — flip, then
            // scale, then draw.
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    // MARK: - Vision reading primitives
    //
    // Everything below is `async` and lives outside any actor, so an `await`
    // from the @MainActor view model runs it on the cooperative pool. Rendering
    // and JPEG-encoding a page is tens of milliseconds of CPU that must never
    // sit on the main thread while a progress line is animating.

    /// Page count and the same pre-flight `extract(pdfData:)` applies, so the
    /// vision path rejects a locked or corrupt file before it renders anything.
    static func pageCount(pdfData: Data) async throws -> Int {
        guard let doc = PDFDocument(data: pdfData) else { throw IntakeError.unreadable }
        if doc.isLocked { throw IntakeError.encrypted }
        return doc.pageCount
    }

    /// One page, rendered once, as both the base64 a vision model reads and the
    /// `UIImage` the OCR fallback for that page reads.
    ///
    /// `base64` is `nil` when the page will not fit `visionMaxJPEGBytes` at any
    /// rung of the ladder; the image is still returned, so that page degrades to
    /// OCR without a second render.
    ///
    /// `PDFDocument(data:)` is re-created per call rather than held across the
    /// loop because `PDFDocument` is not `Sendable` and the loop that drives
    /// this lives on the main actor. PDFKit parsing is lazy, so the per-page
    /// cost is the draw — which is paid either way.
    static func pageJPEGBase64(
        pdfData: Data,
        index: Int,
        longestSide: CGFloat = visionLongestSide,
        quality: CGFloat = visionJPEGQuality
    ) async -> (base64: String?, image: UIImage)? {
        guard
            let doc = PDFDocument(data: pdfData),
            index >= 0, index < doc.pageCount,
            let page = doc.page(at: index),
            let image = rasterise(page: page, longestSide: longestSide)
        else { return nil }
        return (jpegBase64Sync(image, longestSide: longestSide, quality: quality), image)
    }

    /// One page's embedded text layer, trimmed, or `""` when the page carries
    /// none worth reading.
    ///
    /// The vision path's per-page fallback consults this before it OCRs a
    /// render, for exactly the reason `extract(pdfData:)` does: a born-digital
    /// worksheet already holds the exact Arabic and the exact `\frac`, and
    /// rasterising it so Vision can guess at it again is strictly worse. The
    /// `minPageTextChars` decision stays with the caller, which needs to know
    /// how much text there was in order to pick the better of the two readings.
    static func pageText(pdfData: Data, index: Int) async -> String {
        guard
            let doc = PDFDocument(data: pdfData),
            index >= 0, index < doc.pageCount,
            let page = doc.page(at: index)
        else { return "" }
        return page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// One page rendered for on-device OCR alone — the pages after vision has
    /// been latched off for the rest of the file. They get the OCR clamp back
    /// rather than the vision one, since no token budget is riding on them any
    /// more, and they skip the JPEG encode entirely.
    static func pageImage(
        pdfData: Data,
        index: Int,
        longestSide: CGFloat = 2600
    ) async -> UIImage? {
        guard
            let doc = PDFDocument(data: pdfData),
            index >= 0, index < doc.pageCount,
            let page = doc.page(at: index)
        else { return nil }
        return rasterise(page: page, longestSide: longestSide)
    }

    /// A photographed page — the single-photo chat path and the image-file
    /// intake path both come through here.
    static func jpegBase64(
        _ image: UIImage,
        longestSide: CGFloat = visionLongestSide,
        quality: CGFloat = visionJPEGQuality
    ) async -> String? {
        jpegBase64Sync(image, longestSide: longestSide, quality: quality)
    }

    /// The re-encode ladder: q75 → q60 → q45 → 1152 px @ q60 → give up.
    ///
    /// A dense text page at q75 lands around 120–220 KB, so the ladder is a
    /// guard rail rather than a routine cost. Giving up returns `nil`, which the
    /// caller reads as "OCR this page" — never as "fail the file".
    private static func jpegBase64Sync(
        _ image: UIImage,
        longestSide: CGFloat,
        quality: CGFloat
    ) -> String? {
        let scaled = downscale(image, longestSide: longestSide) ?? image
        for rung in [quality, 0.60, 0.45] {
            if let data = scaled.jpegData(compressionQuality: rung),
               data.count <= visionMaxJPEGBytes {
                // `base64EncodedString()` is unwrapped by default. Line breaks
                // in the payload are a 400 from Gemini, so no options here.
                return data.base64EncodedString()
            }
        }
        if let smaller = downscale(image, longestSide: visionSmallLongestSide),
           let data = smaller.jpegData(compressionQuality: 0.60),
           data.count <= visionMaxJPEGBytes {
            return data.base64EncodedString()
        }
        return nil
    }

    /// Shrinks to a longest-side clamp, never enlarges — upscaling a photo adds
    /// bytes and no information. Pixel dimensions come from `size × scale` so a
    /// rotated camera photo is measured after its orientation is applied.
    private static func downscale(_ image: UIImage, longestSide: CGFloat) -> UIImage? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let maxSide = max(pixelWidth, pixelHeight)
        guard maxSide > 1, pixelWidth > 1, pixelHeight > 1 else { return nil }
        if maxSide <= longestSide { return image }

        let ratio = longestSide / maxSide
        let target = CGSize(
            width: max(1, (pixelWidth * ratio).rounded()),
            height: max(1, (pixelHeight * ratio).rounded()))

        // scale = 1 so the bitmap is exactly `target` pixels rather than
        // `target × screen scale`, matching `rasterise` and Android's
        // `Bitmap.createBitmap(w, h)`.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: - Parse the model's segmentation reply

    /// Turns the model's reply into questions, or `nil` when the reply is not
    /// a JSON array at all.
    ///
    /// The `nil`/`[]` distinction is load-bearing: `nil` means "the model did
    /// not answer the question we asked" and triggers the regex fallback,
    /// while `[]` is a real answer — "this file has no questions in it" — and
    /// must be believed unless the raw text is plainly numbered (§3.5 C).
    static func parseQuestionArray(_ raw: String) -> [String]? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip a ```json … ``` fence. Models add one perhaps one time in ten
        // no matter how firmly the prompt forbids it.
        if text.hasPrefix("```") {
            if let newline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newline)...])
            } else {
                text = ""
            }
            if text.hasSuffix("```") { text = String(text.dropLast(3)) }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard
            let start = text.firstIndex(of: "["),
            let end = text.lastIndex(of: "]"),
            start < end
        else { return nil }

        // Repair is a RESCUE, not a pre-pass. `repairLatexEscapes` doubles any
        // backslash before a letter so `\frac` survives JSON decoding — but
        // `\n` is also a backslash before a letter, so running it over a reply
        // that was already valid JSON turns every newline into the two literal
        // characters `\n`. That is what put "…\na) \frac{\pi}{2}\nb)" on
        // screen instead of one option per line. So: parse first, and only
        // repair the replies that genuinely failed to parse.
        let slice = String(text[start...end])

        // Parse first, repair only on evidence of damage.
        //
        // The repair doubles every backslash before a letter so `\frac` survives
        // — but `\n` is a backslash before a letter too, so running it over a
        // reply that was ALREADY valid JSON turns each newline into the two
        // literal characters `\n`. That is what put "…\na) \frac{\pi}{2}\nb)"
        // on screen instead of one option per line.
        //
        // Parsing first is not enough on its own, because `\f`, `\b` and `\v`
        // are *valid* JSON escapes: `"$\frac{1}{2}$"` parses without error into
        // `$<U+000C>rac{1}{2}$`, silently corrupted. So the parse is accepted only
        // when it carries none of those control characters — which no real
        // question ever contains, while a newline is perfectly legitimate and is
        // deliberately not on the list.
        if let clean = slice.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: clean),
           let array = object as? [Any] {
            let collected = collectQuestions(array)
            if !collected.contains(where: mangledByJSONEscape) {
                return collected
            }
        }

        guard
            let data = repairLatexEscapes(slice).data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let array = object as? [Any]
        else { return nil }

        return collectQuestions(array)
    }

    /// Backspace, form feed and vertical tab: three JSON escapes a LaTeX command
    /// can be silently swallowed into (`\b`eta, `\f`rac, `\v`ec). None of them
    /// has any business in a worksheet question, so one of them is damage on
    /// sight.
    ///
    /// TAB and CR are the same hazard and were missing: `\t`heta, `\t`imes,
    /// `\t`o, `\t`an and `\r`ight are commands the prompts actively ask for, and
    /// `["Compute $2 \times 5$"]` decodes without any error at all into
    /// `$2 <TAB>imes 5$`, so the first parse was accepted and `2 imes 5` was
    /// typeset as italic letters on the card, in the bubble and in the PDF.
    /// Unlike the other three, though, a tab or a carriage return can also be
    /// deliberate whitespace, and a false alarm here is not free — it sends a
    /// perfectly good reply through `repairLatexEscapes`, which rewrites every
    /// `\n` to a literal backslash-n. So the test is what FOLLOWS: a swallowed
    /// command always leaves the rest of its name behind, which means an ASCII
    /// letter, while `\r\n` and a tab used for spacing do not.
    ///
    /// A newline is not on this list in any form — models legitimately separate
    /// a stem from its options with one, and both extraction prompts now require
    /// it.
    private static func mangledByJSONEscape(_ s: String) -> Bool {
        let scalars = Array(s.unicodeScalars)
        for (i, scalar) in scalars.enumerated() {
            if scalar == "\u{0008}" || scalar == "\u{000C}" || scalar == "\u{000B}" {
                return true
            }
            guard scalar == "\u{0009}" || scalar == "\u{000D}", i + 1 < scalars.count else {
                continue
            }
            let next = scalars[i + 1].value
            if (next >= 0x41 && next <= 0x5A) || (next >= 0x61 && next <= 0x7A) {
                return true
            }
        }
        return false
    }

    private static func collectQuestions(_ array: [Any]) -> [String] {
        var questions: [String] = []
        for element in array {
            guard let string = element as? String else { continue }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= minQuestionChars else { continue }
            if questions.last == trimmed { continue }
            questions.append(trimmed)
        }
        return questions
    }

    /// Doubles the backslash of every LaTeX command so the JSON parser sees the
    /// maths the model meant, not a control character.
    ///
    /// This is the one repair that silently ruins the feature if it is skipped.
    /// `\f` is a *valid* JSON escape: a reply containing `"$\frac{1}{2}$"`
    /// parses without error into `$<U+000C>rac{1}{2}$`, so the formula is
    /// corrupted and nothing anywhere reports a problem. `\b` (`\beta`), `\n`
    /// (`\ne`), `\r` (`\right`) and `\t` (`\theta`, `\times`) do the same. `\s`
    /// (`\sqrt`) is an *invalid* escape, where Android's lenient `org.json`
    /// yields `sqrt` and Swift's strict `JSONSerialization` fails outright — so
    /// without this the two apps would diverge on the same reply, one silently
    /// corrupting and one falling back to the regex.
    ///
    /// A character scan rather than a regex: the patterns in this file are
    /// deliberately brace-free so they stay byte-comparable with the Android
    /// ones, where ICU treats a bare brace as a runtime pattern-compile error —
    /// and `\\frac{a}{b}` is nothing but braces.
    ///
    /// Shared with the OCR/segmentation path on purpose: models emit half-escaped
    /// LaTeX just as unevenly there. What makes that sharing safe is no longer a
    /// clause in the prompts — both extraction prompts now REQUIRE a real newline
    /// between a stem and each answer option, because the review sheet has to put
    /// one option per line. What makes it safe is `parseQuestionArray` calling
    /// this only as a RESCUE: the reply is parsed as it stands first, and this
    /// repair runs only when that parse failed outright or came back carrying
    /// U+0008 / U+000C / U+000B — the three control characters a swallowed
    /// `\beta` / `\frac` / `\vec` leaves behind. A legitimate `\n` is still
    /// indistinguishable from `\ne` in here and is still rewritten to a literal
    /// backslash-n; on a reply that already failed to parse, a mangled newline is
    /// an acceptable price for getting any questions at all. Never call this
    /// ahead of a parse.
    static func repairLatexEscapes(_ raw: String) -> String {
        guard raw.contains("\\") else { return raw }

        let chars = Array(raw)
        var out = ""
        out.reserveCapacity(chars.count + 32)

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c != "\\" {
                out.append(c)
                i += 1
                continue
            }
            // A trailing lone backslash cannot be an escape of anything.
            guard i + 1 < chars.count else {
                out.append("\\\\")
                i += 1
                continue
            }
            let next = chars[i + 1]
            // Already-correct JSON escapes: leave them exactly as they are.
            if next == "\\" || next == "\"" || next == "/" {
                out.append(c)
                out.append(next)
                i += 2
                continue
            }
            // A real \uXXXX escape — four hex digits, ASCII only.
            if next == "u", i + 5 < chars.count,
               chars[(i + 2)...(i + 5)].allSatisfy({ $0.isASCII && $0.isHexDigit }) {
                out.append(c)
                out.append(next)
                i += 2
                continue
            }
            // \frac, \sqrt, \times, \ne … — a LaTeX command, not an escape.
            if next.isASCII, next.isLetter {
                out.append("\\\\")
                out.append(next)
                i += 2
                continue
            }
            out.append(c)
            out.append(next)
            i += 2
        }
        return out
    }

    // MARK: - Deterministic fallback

    /// Splits a worksheet into questions with no network and no model.
    ///
    /// Runs when the provider chain is exhausted or the reply is unparseable,
    /// so it has to be dependable rather than clever. Pure function, so it can
    /// be exercised without a provider.
    static func segmentByPattern(_ text: String) -> [String] {
        Array(patternSlices(text).prefix(maxQuestions))
    }

    /// `segmentByPattern` without the cap, so the caller can tell a 41-question
    /// sheet (worth a notice) from a 40-question one.
    static func patternSlices(_ text: String) -> [String] {
        let normalised = normalise(text)

        // Numbered questions: "1." / "Q3)" / "س ٤-". Two markers is the
        // threshold — a lone "1." is far more likely to be a date or a step
        // inside a single question than the start of a numbered list.
        let ns = normalised as NSString
        if let regex = try? NSRegularExpression(pattern: Pattern.marker) {
            let matches = regex.matches(
                in: normalised, range: NSRange(location: 0, length: ns.length))
            if matches.count >= 2 {
                var slices: [String] = []
                for (index, match) in matches.enumerated() {
                    // Start after the marker so the question keeps its own
                    // text but loses the sheet's numbering, which the export
                    // renumbers anyway.
                    let start = match.range.location + match.range.length
                    let end = index + 1 < matches.count
                        ? matches[index + 1].range.location
                        : ns.length
                    guard end > start else { continue }
                    slices.append(ns.substring(with: NSRange(location: start, length: end - start)))
                }
                return tidy(slices)
            }
        }

        // Unnumbered sheet: treat blank-line-separated paragraphs as
        // questions, but only ones carrying a digit or an operator. That drops
        // the title, the school name and "Answer all questions" without
        // needing a list of them.
        let sentinel = "\u{1}"
        let split = normalised.replacingOccurrences(
            of: Pattern.paragraph, with: sentinel, options: .regularExpression)
        let paragraphs = split
            .components(separatedBy: sentinel)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 12 && $0.range(of: Pattern.mathy, options: .regularExpression) != nil }
        if paragraphs.count >= 2 { return tidy(paragraphs) }

        // Neither shape matched, so this is one question — which is exactly
        // what the camera flow has always produced, and a legitimate outcome
        // rather than a failure.
        return tidy([normalised])
    }

    /// Patterns are written without a single brace — not even `[0-9]{1,3}` —
    /// so this file stays byte-comparable with the Android one, where ICU
    /// treats a bare brace as a pattern-compile error at runtime.
    private enum Pattern {
        /// `.`, `)`, `:` and the Arabic full stop are unambiguous numbering
        /// separators. A hyphen is not: "8 - 5 = ?" has exactly the shape of
        /// "8 - Solve for x", and treating it as numbering swallows the first
        /// operand of every arithmetic line on the sheet, so the tutor is asked
        /// to solve "5 = ?" and the export prints that as the student's
        /// problem. The hyphen branch therefore refuses to fire when what
        /// follows starts like the rest of a sum — a digit, `=`, or an
        /// operator. "1- Solve", "1 - Solve" and "١- احسب" all still match.
        static let marker =
            "(?m)^[ \\t]*(?:[QqسS][ \\t]*[.):\\-]?[ \\t]*)?([0-9\u{0660}-\u{0669}]+)[ \\t]*"
            + "(?:[.):\u{06D4}][ \\t]+|-[ \\t]+(?![0-9\u{0660}-\u{0669}=+\\-\u{00D7}\u{00F7}]))"
        static let paragraph = "\n[ \\t]*\n"
        static let mathy = "[0-9\u{0660}-\u{0669}?\u{061F}=+\\-\u{00D7}\u{00F7}\u{222B}\u{221A}]"
    }

    private static func normalise(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
    }

    /// Trim, drop stubs, drop consecutive duplicates. Consecutive rather than
    /// global because a worksheet legitimately repeats "Simplify:" as separate
    /// questions, while OCR of a two-column scan duplicates a line in place.
    private static func tidy(_ raw: [String]) -> [String] {
        var out: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= minQuestionChars else { continue }
            if out.last == trimmed { continue }
            out.append(trimmed)
        }
        return out
    }
}
