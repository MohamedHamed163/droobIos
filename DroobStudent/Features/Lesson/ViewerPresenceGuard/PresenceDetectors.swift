import Foundation
import Vision
import CoreImage
import CoreML
import AVFoundation

// MARK: - Tier 0 — Face counting (cheap, runs often)
//
// Vision's `VNDetectFaceRectanglesRequest` needs no model download and is
// hardware-accelerated. It drives the 0 / 1 / 2+ logic and supplies the face
// boxes the identity tier crops from. Runs synchronously on the capture
// queue — Vision is happy off the main thread.

struct FaceDetectionResult {
    let faceCount: Int
    /// The largest face box (normalized, Vision's bottom-left origin), used by
    /// Tier 1 to crop. Nil when no face.
    let largestFace: VNFaceObservation?
    /// Average frame luma in 0…1 — feeds the low-light vs no-face decision.
    let luma: Double
}

final class FaceCounter {
    private let sequenceHandler = VNSequenceRequestHandler()

    /// Counts faces and measures brightness in one pass. `orientation` should
    /// match how the buffer is oriented for an upright face.
    func analyze(_ pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation) -> FaceDetectionResult {
        let luma = Self.averageLuma(pixelBuffer)

        let request = VNDetectFaceRectanglesRequest()
        // Default revision; counting doesn't need landmarks/classification.
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: orientation)
        } catch {
            // A failed Vision pass is treated as "couldn't see" rather than
            // "no one there" — let the brightness gate decide downstream.
            return FaceDetectionResult(faceCount: 0, largestFace: nil, luma: luma)
        }
        let faces = request.results ?? []
        let largest = faces.max { a, b in
            a.boundingBox.area < b.boundingBox.area
        }
        return FaceDetectionResult(faceCount: faces.count, largestFace: largest, luma: luma)
    }

    /// Cheap average-luma estimate. Reads the Y plane of a 420 buffer on a
    /// sparse grid (every ~16th pixel) so it costs microseconds and never
    /// touches the render path.
    static func averageLuma(_ pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // Planar (YpCbCr 420) — read plane 0 (luma) directly.
        if CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
           let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
            let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            var sum = 0
            var n = 0
            let step = 16
            var y = 0
            while y < height {
                var x = 0
                let row = y * stride
                while x < width {
                    sum += Int(ptr[row + x]); n += 1
                    x += step
                }
                y += step
            }
            return n > 0 ? Double(sum) / Double(n) / 255.0 : 0
        }
        return 0.5  // unknown format — assume mid brightness (don't false-flag low light)
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}

// MARK: - Tier 2 — Phone / screen / recording-device detection (model-free)
//
// Uses Vision's built-in scene classifier (`VNClassifyImageRequest`) — no
// model download — to spot a phone, tablet, TV, monitor or screen in frame
// (e.g. someone pointing a second phone at the display to record). It returns
// scene-level identifiers with confidences; we match the ones that imply a
// recording/display device. Coarser than a YOLO detector (no bounding box)
// and can false-positive, so the engine debounces it and surfaces it as an
// alert rather than a hard block by default. Runs on a slow cadence.

struct PhoneDetectionResult {
    let detected: Bool
    /// The matched identifier / signal (for logging / debugging), if any.
    let label: String?
    /// Confidence of the match.
    let confidence: Float
    /// Human-readable summary of what the detectors saw this pass — surfaced
    /// in the test harness so detection can be tuned on-device.
    let diagnostic: String
}

/// Two complementary, model-free signals:
///   1. **Scene classification** (`VNClassifyImageRequest`) — matches phone /
///      screen / monitor / laptop / TV identifiers. Good when the device
///      dominates the frame; weaker when it's small next to a face.
///   2. **Rectangle detection** (`VNDetectRectanglesRequest`) — a phone or
///      screen pointed at the camera is a bright quadrilateral; this catches
///      it even when classification misses. This is what makes "phone held up
///      to record" actually fire.
/// A positive from EITHER signal counts (the engine debounces).
final class PhoneScreenDetector {
    private let handler = VNSequenceRequestHandler()
    private let threshold: Float

    /// Substrings (lowercased) that imply a recording/display device.
    private let keywords = [
        "phone", "telephon", "cellular", "smartphone", "cellphone",
        "screen", "television", "monitor", "laptop", "tablet",
        "display", "computer", "ipod", "remote_control", "camera"
    ]

    init(threshold: Float) { self.threshold = threshold }

    func detect(_ pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation) -> PhoneDetectionResult {
        let classify = VNClassifyImageRequest()

        let rectangles = VNDetectRectanglesRequest()
        rectangles.minimumAspectRatio = 0.3      // phones/screens are fairly rectangular…
        rectangles.maximumAspectRatio = 1.0      // …up to square
        rectangles.minimumSize = 0.10            // ≥10% of the frame (a held-up phone)
        rectangles.maximumObservations = 8
        rectangles.minimumConfidence = 0.6
        rectangles.quadratureTolerance = 35

        do {
            try handler.perform([classify, rectangles], on: pixelBuffer, orientation: orientation)
        } catch {
            return PhoneDetectionResult(detected: false, label: nil, confidence: 0, diagnostic: "error")
        }

        // --- Signal 1: classification ---
        var matchedLabel: String?
        var matchedConf: Float = 0
        var top3 = "—"
        if let results = classify.results, !results.isEmpty {
            let sorted = results.sorted { $0.confidence > $1.confidence }
            top3 = sorted.prefix(3)
                .map { "\($0.identifier) \(String(format: "%.2f", $0.confidence))" }
                .joined(separator: ", ")
            for obs in sorted where obs.confidence >= threshold {
                if keywords.contains(where: { obs.identifier.lowercased().contains($0) }) {
                    matchedLabel = obs.identifier
                    matchedConf = obs.confidence
                    break
                }
            }
        }

        // --- Signal 2: screen-like rectangle (sizable, not the whole frame) ---
        let rects = rectangles.results ?? []
        let screenRect = rects.first { r in
            let area = r.boundingBox.width * r.boundingBox.height
            return area > 0.05 && area < 0.85
        }
        let rectHit = screenRect != nil

        let detected = matchedLabel != nil || rectHit
        let label = matchedLabel ?? (rectHit ? "screen-rectangle" : nil)
        let diagnostic = "class[\(top3)] rect:\(rects.count)\(rectHit ? "✓" : "")"
        return PhoneDetectionResult(detected: detected,
                                    label: label,
                                    confidence: matchedConf,
                                    diagnostic: diagnostic)
    }
}

// MARK: - Face cropping (shared by Tier 1 / 1.5)

/// Crops the detected face out of the full frame and resizes it to a square
/// for the embedding / liveness models. One shared `CIContext` (GPU-backed)
/// is reused — no per-frame allocations in the hot path.
final class FaceCropper {
    private let ciContext: CIContext
    private var pool: CVPixelBufferPool?
    private var poolSize: Int = 0

    init(useHardwareAccel: Bool) {
        ciContext = CIContext(options: [.useSoftwareRenderer: !useHardwareAccel])
    }

    /// Returns a BGRA pixel buffer of `side`×`side` containing the face box
    /// (expanded by `margin`) from `source`. Vision boxes use a bottom-left
    /// normalized origin, so we flip Y into image space first.
    func crop(_ source: CVPixelBuffer,
              face: VNFaceObservation,
              side: Int,
              margin: CGFloat = 0.25) -> CVPixelBuffer? {
        let w = CGFloat(CVPixelBufferGetWidth(source))
        let h = CGFloat(CVPixelBufferGetHeight(source))

        var box = face.boundingBox
        box = box.insetBy(dx: -box.width * margin, dy: -box.height * margin)
        // Vision normalized (bottom-left) → pixel rect (top-left).
        let px = box.origin.x * w
        let py = (1 - box.origin.y - box.height) * h
        let rect = CGRect(x: px, y: py, width: box.width * w, height: box.height * h)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isNull, rect.width > 1, rect.height > 1 else { return nil }

        let image = CIImage(cvPixelBuffer: source)
            .cropped(to: CGRect(x: rect.minX, y: h - rect.maxY, width: rect.width, height: rect.height))
        let scale = CGFloat(side) / max(rect.width, rect.height)
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -(h - rect.maxY)))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let out = makeBuffer(side: side) else { return nil }
        ciContext.render(scaled, to: out)
        return out
    }

    private func makeBuffer(side: Int) -> CVPixelBuffer? {
        if pool == nil || poolSize != side {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: side,
                kCVPixelBufferHeightKey as String: side,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            var newPool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &newPool)
            pool = newPool
            poolSize = side
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }
}

// MARK: - Tier 1 — Identity match (medium, runs rarely)

/// Produces an L2-normalized face embedding. Backed by a MobileFaceNet-class
/// Core ML model when one is bundled; absent that, the factory returns nil
/// and the identity tier stays inactive (face counting + watermark still
/// enforce on their own).
protocol FaceEmbedder: AnyObject {
    func embedding(from faceCrop: CVPixelBuffer) throws -> [Float]
}

/// Probability in 0…1 that a face crop is a live, present person (not a
/// printed photo, screen, or replay). Backed by a MiniFASNet / Silent-Face
/// model when bundled.
protocol LivenessClassifier: AnyObject {
    func livenessProbability(from faceCrop: CVPixelBuffer) throws -> Float
}

/// Cosine distance (1 − cosine similarity) between two embeddings. 0 = same.
func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 2 }
    var dot: Float = 0, na: Float = 0, nb: Float = 0
    for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
    let denom = (na.squareRoot() * nb.squareRoot())
    guard denom > 0 else { return 2 }
    return 1 - (dot / denom)
}

// MARK: Core ML adapters
//
// Generic adapters that drive any single-image-in / array-out (embedder) or
// single-image-in / score-out (liveness) Core ML model. They introspect the
// model's feature descriptions so we don't hard-code names, and resize the
// face crop to the model's exact required input. The exact I/O of the real
// converted model should be validated once it's dropped into the bundle.

final class CoreMLFaceEmbedder: FaceEmbedder {
    private let model: MLModel
    private let inputName: String
    private let inputSize: (width: Int, height: Int)
    private let outputName: String
    private let ciContext: CIContext

    init?(modelName: String, useHardwareAccel: Bool) {
        guard let model = CoreMLLoader.load(modelName, useHardwareAccel: useHardwareAccel),
              let img = CoreMLLoader.firstImageInput(model),
              let out = CoreMLLoader.firstMultiArrayOutput(model) else { return nil }
        self.model = model
        self.inputName = img.name
        self.inputSize = img.size
        self.outputName = out
        self.ciContext = CIContext(options: [.useSoftwareRenderer: !useHardwareAccel])
    }

    func embedding(from faceCrop: CVPixelBuffer) throws -> [Float] {
        let resized = CoreMLLoader.resize(faceCrop, to: inputSize, context: ciContext) ?? faceCrop
        let provider = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(pixelBuffer: resized)])
        let out = try model.prediction(from: provider)
        guard let arr = out.featureValue(for: outputName)?.multiArrayValue else { return [] }
        var vec = [Float](repeating: 0, count: arr.count)
        for i in 0..<arr.count { vec[i] = arr[i].floatValue }
        // L2 normalize so cosine distance is well-conditioned.
        let norm = vec.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if norm > 0 { for i in 0..<vec.count { vec[i] /= norm } }
        return vec
    }
}

final class CoreMLLivenessClassifier: LivenessClassifier {
    private let model: MLModel
    private let inputName: String
    private let inputSize: (width: Int, height: Int)
    private let ciContext: CIContext

    init?(modelName: String, useHardwareAccel: Bool) {
        guard let model = CoreMLLoader.load(modelName, useHardwareAccel: useHardwareAccel),
              let img = CoreMLLoader.firstImageInput(model) else { return nil }
        self.model = model
        self.inputName = img.name
        self.inputSize = img.size
        self.ciContext = CIContext(options: [.useSoftwareRenderer: !useHardwareAccel])
    }

    func livenessProbability(from faceCrop: CVPixelBuffer) throws -> Float {
        let resized = CoreMLLoader.resize(faceCrop, to: inputSize, context: ciContext) ?? faceCrop
        let provider = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(pixelBuffer: resized)])
        let out = try model.prediction(from: provider)
        // Accept either a dictionary (label→prob) or a 2-class array output.
        for name in out.featureNames {
            guard let fv = out.featureValue(for: name) else { continue }
            if let dict = fv.dictionaryValue as? [String: NSNumber] {
                for (k, v) in dict where k.lowercased().contains("live") || k.lowercased().contains("real") {
                    return v.floatValue
                }
            }
            if let arr = fv.multiArrayValue, arr.count >= 2 {
                // Convention: index 1 = "live" probability.
                return arr[1].floatValue
            }
        }
        return 1  // unknown output shape — don't false-accuse; treat as live.
    }
}

// MARK: - CoreML loading helpers

enum CoreMLLoader {
    /// Loads a compiled (`.mlmodelc`) or source (`.mlmodel`/`.mlpackage`)
    /// model from the main bundle by name. Returns nil when absent so callers
    /// degrade gracefully. Logged once per missing model.
    static func load(_ name: String, useHardwareAccel: Bool) -> MLModel? {
        let cfg = MLModelConfiguration()
        cfg.computeUnits = useHardwareAccel ? .all : .cpuOnly

        if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
           let m = try? MLModel(contentsOf: url, configuration: cfg) {
            return m
        }
        // Allow shipping an uncompiled model too (compile on first use).
        for ext in ["mlpackage", "mlmodel"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let compiled = try? MLModel.compileModel(at: url),
               let m = try? MLModel(contentsOf: compiled, configuration: cfg) {
                return m
            }
        }
        NSLog("[PresenceGuard] CoreML model '\(name)' not bundled — tier inactive")
        return nil
    }

    static func firstImageInput(_ model: MLModel) -> (name: String, size: (width: Int, height: Int))? {
        for (name, desc) in model.modelDescription.inputDescriptionsByName {
            if let img = desc.imageConstraint {
                return (name, (img.pixelsWide, img.pixelsHigh))
            }
        }
        return nil
    }

    static func firstMultiArrayOutput(_ model: MLModel) -> String? {
        for (name, desc) in model.modelDescription.outputDescriptionsByName {
            if desc.multiArrayConstraint != nil { return name }
        }
        return model.modelDescription.outputDescriptionsByName.keys.first
    }

    /// Renders `buffer` into a fresh BGRA buffer of the requested size.
    static func resize(_ buffer: CVPixelBuffer,
                       to size: (width: Int, height: Int),
                       context: CIContext) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        if w == size.width && h == size.height { return buffer }
        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height,
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard let out else { return nil }
        let scaleX = CGFloat(size.width) / CGFloat(w)
        let scaleY = CGFloat(size.height) / CGFloat(h)
        let img = CIImage(cvPixelBuffer: buffer)
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        context.render(img, to: out)
        return out
    }
}

// MARK: - Model factory (graceful degradation)

/// Resolves the optional ML tiers. When a model isn't bundled the matching
/// detector is nil and that tier silently no-ops — Tier 0 + watermark keep
/// working. Drop these compiled models into the app target to activate:
///   • `MobileFaceNet`           — Tier 1 identity embedder
///   • `SilentFaceAntiSpoofing`  — Tier 1.5 passive liveness
enum PresenceModelFactory {
    static let identityModelName = "MobileFaceNet"
    static let livenessModelName = "SilentFaceAntiSpoofing"

    static func makeEmbedder(_ config: PresenceGuardConfig) -> FaceEmbedder? {
        CoreMLFaceEmbedder(modelName: identityModelName,
                           useHardwareAccel: config.useHardwareAccel)
    }

    static func makeLiveness(_ config: PresenceGuardConfig) -> LivenessClassifier? {
        guard config.livenessEnabled else { return nil }
        return CoreMLLivenessClassifier(modelName: livenessModelName,
                                        useHardwareAccel: config.useHardwareAccel)
    }
}
