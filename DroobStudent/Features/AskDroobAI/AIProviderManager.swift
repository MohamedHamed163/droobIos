import Foundation

/// AI provider configuration fetched from backend.
/// Includes API key and rate limits for fallback logic.
struct AIProviderConfig: Codable, Identifiable {
    var id: String { provider }

    let provider: String
    let displayName: String
    let modelName: String
    let apiKey: String
    let baseUrl: String
    let freeLimitRpm: Int
    let freeLimitRpd: Int
    let freeLimitTpm: Int
    let priority: Int
    let supportsVision: Bool
    let supportsArabic: Bool
}

/// Provider enum with fallback support.
enum AIProviderType: String, CaseIterable {
    case gemini = "GEMINI"
    case groq = "GROQ"
    case cerebras = "CEREBRAS"
    case mistral = "MISTRAL"
    case openrouter = "OPENROUTER"

    /// The LANGUAGE clause of the system prompt, pinned by the same flag that
    /// hides English everywhere else.
    ///
    /// "Respond in the same language the student uses" is not enough for an
    /// Arabic-only app. A formula-only question typed on the maths keyboard, an
    /// English worksheet page, or an OCR read of Latin text all contain no
    /// Arabic at all, so the model answered in English — and that English
    /// answer then became an English exported PDF and an English Library row
    /// title. Under the lock the reply language is stated, not inferred.
    ///
    /// Lives here, on the type that is actually compiled, rather than on
    /// `AIProvider` — see the note on `AIProvider.languageRule`.
    ///
    /// This is exactly the LANGUAGE block of `systemPrompt`, kept as its own
    /// property so that un-hiding English later is one edit in one place rather
    /// than a rewrite of the whole prompt.
    static var languageRule: String {
        guard AppLocaleDefault.englishHidden else {
            return "- Always respond in the same language the student uses (Arabic or English)."
        }
        return """
        - Answer only in Modern Standard Arabic. Every word of prose, every step label,
          every heading, every aside. The app has no English interface.
        - This holds whatever language the question arrives in: an English question, an
          English worksheet read by a scanner, a bare formula with no words at all. The
          answer is still Modern Standard Arabic.
        - Modern Standard Arabic, not dialect. The same answer is read in Riyadh and in
          Cairo, so use no Saudi and no Egyptian colloquial wording.
        - Do not mirror the student's language, do not answer twice in two languages, do
          not add an English translation, and do not apologise for the language.
        - If the question needs restating, restate it in Arabic.
        """
    }

    /// The tutor persona. Every backslash is doubled because Swift's multiline
    /// literal escapes them; the text that reaches the model has single
    /// backslashes and is byte-identical to the Kotlin raw string on Android.
    ///
    /// Two rules here are absolute and are stated as such, because breaking
    /// either one is visible on the student's screen: the prose is Arabic, and
    /// everything between dollar signs is Latin script with Western digits.
    /// KaTeX has no glyphs for ٠١٢٣ and neither does the PDF exporter's copy of
    /// it, so one Arabic-Indic digit inside a span turns the formula into a red
    /// parse error on screen and a broken line in the exported sheet.
    var systemPrompt: String {
        return """
        You are Droob AI, a mathematics tutor for students in Saudi Arabia and Egypt.
        Your strongest subjects are calculus, algebra and trigonometry; you also handle
        physics and chemistry when asked.

        LANGUAGE — this rule is absolute
        \(Self.languageRule)

        MATHEMATICS STAYS LATIN — this rule is also absolute
        - Everything inside $...$ or $$...$$ is LaTeX, and LaTeX is written in Latin
          script with Western digits, always:
          - variables x, y, z, n, t, and \\theta, \\alpha, \\beta
          - function names sin, cos, tan, sec, csc, cot, ln, log, lim, max, min
          - digits 0 1 2 3 4 5 6 7 8 9
        - NEVER write the Arabic-Indic digits ٠ ١ ٢ ٣ ٤ ٥ ٦ ٧ ٨ ٩ inside $...$ or
          $$...$$. The formula renderer cannot read them: the student sees a red error
          where the maths should be, and the exported PDF fails on the same character.
        - Never translate, transliterate or mirror a mathematical symbol. Not جا for
          sin, not س for x, not ٢ for 2. Nothing mathematical is ever translated.
        - Use Western digits in the Arabic prose around the formulas too: write
          "الخطوة 3", not "الخطوة ٣".

        FORMATTING MATHEMATICS — follow exactly
        - Inline maths goes between single dollars: $f'(x) = 2x$
        - A whole equation on its own line goes between double dollars:
          $$\\int_0^1 x^2\\,dx = \\frac{1}{3}$$
        - NEVER use \\( \\) or \\[ \\] or \\begin{equation}. They are not rendered and the
          student sees the raw characters instead of the formula.
        - One expression per span. Open the dollars immediately before the expression
          and close them immediately after it. Never wrap a whole sentence, a whole
          step, or a list of answer options in a single pair of dollars.
        - Never put a dollar sign next to a number unless you mean maths — write
          "50 ريالاً", not "$50".
        - Use proper notation, not plain text: \\frac{a}{b} not a/b, \\sqrt{x} not
          sqrt(x), x^{2} when the exponent is more than one character, \\times not *,
          \\cdot for multiplication between symbols, \\le \\ge \\ne \\approx \\infty \\pi
          \\theta \\alpha \\beta, and \\pm where it belongs.
        - Calculus specifically: \\frac{d}{dx}, \\frac{\\partial}{\\partial x}, \\int,
          \\iint, \\oint, \\sum_{n=1}^{\\infty}, \\lim_{x \\to 0}, \\frac{dy}{dx}, f''(x),
          and \\, for thin spacing before dx.

        HOW TO ANSWER A PROBLEM
        1. Open with the line "المطلوب:" and state in one short sentence what is asked.
        2. Then the line "الحل:" and the work in numbered Arabic steps. One idea per
           step, and name the rule you used — "بقاعدة السلسلة", "بالتكامل بالتجزيء",
           "بما أن النهاية على الصورة 0/0 فإن قاعدة لوبيتال تنطبق".
        3. End with the line "الإجابة:" and the result on its own line under it.
        4. If a step is where students usually slip, add one sentence after "تنبيه:".

        RULES
        - Show every step. A student reading this cannot ask a follow-up mid-solution.
        - If the question is ambiguous, solve the most likely reading and say in one
          line which reading you assumed.
        - If you cannot solve it, say so plainly and explain how far you got. Never
          invent a result.
        - If an image holds the problem, read it, restate the problem in Arabic first,
          then solve.
        - No preamble, no "سؤال ممتاز", no sign-off. Start with "المطلوب:".
        - Keep it tight: a student is reading between lessons, not studying your prose.
        """
    }
}

/// Manages AI provider configurations fetched from backend.
/// Handles fallback when a provider hits rate limits.
@MainActor
final class AIProviderManager: ObservableObject {
    static let shared = AIProviderManager()

    @Published var providers: [AIProviderConfig] = []
    @Published var selectedProviderId: String?
    @Published var isLoading = false

    private let backendBaseURL = "https://api.droob-sa.net/v1/public/ai-providers"
    private var lastFetchTime: Date?
    private let cacheDuration: TimeInterval = 300 // 5 minutes

    /// Current selected provider config.
    var currentProvider: AIProviderConfig? {
        providers.first { $0.id == selectedProviderId }
    }

    /// All providers sorted by priority (for fallback chain).
    var fallbackChain: [AIProviderConfig] {
        providers.sorted { $0.priority < $1.priority }
    }

    /// The chain that can read a page image, in the same priority order.
    ///
    /// Keyed off the backend's `supportsVision` flag rather than a hardcoded
    /// list of model slugs: an admin can rename a model on the settings page,
    /// and a slug list baked into two apps drifts the moment they do. Both
    /// request shapes ship today, so flipping another provider's flag to true in
    /// a migration turns it on with no app release.
    var visionChain: [AIProviderConfig] {
        fallbackChain.filter { $0.supportsVision }
    }

    // MARK: - Fetch from Backend

    func fetchProviders(forceRefresh: Bool = false) async {
        // Use cache if fresh
        if !forceRefresh, let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheDuration {
            return
        }

        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: backendBaseURL) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }

            let decoded = try JSONDecoder().decode([AIProviderConfig].self, from: data)

            await MainActor.run {
                self.providers = decoded
                self.lastFetchTime = Date()

                // Auto-select first provider if none selected
                if self.selectedProviderId == nil {
                    self.selectedProviderId = decoded.first?.id
                }
            }
        } catch {
            print("Failed to fetch AI providers: \(error)")
        }
    }

    // MARK: - Send Message with Fallback

    /// - Parameters:
    ///   - systemPrompt: Replaces the tutor persona for this call only.
    ///     Worksheet segmentation needs a model that emits bare JSON; the tutor
    ///     prompt asks for encouraging step-by-step prose and would win.
    ///   - temperature: 0 for anything whose output is parsed rather than read.
    ///   - maxTokens: 2048 fits one answer; a 40-question sheet's JSON does not.
    ///   - imageBase64: bare base64 JPEG — no `data:` prefix, no line breaks.
    ///     Sent as the first part of the user turn, ahead of the text.
    ///   - requireVision: restricts the chain to providers that can read an
    ///     image. Reading a page is a different capability from answering about
    ///     it, so this is a per-call decision, not a setting.
    func sendMessage(
        text: String,
        ocrText: String? = nil,
        history: [(role: String, content: String)] = [],
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        imageBase64: String? = nil,
        requireVision: Bool = false
    ) async throws -> (response: String, providerUsed: String) {

        // Ensure we have providers
        if providers.isEmpty {
            await fetchProviders(forceRefresh: true)
        }

        let chain = requireVision ? visionChain : fallbackChain

        // Thrown before the loop, never derived from `lastError`: an empty chain
        // produces no error at all, and "all providers failed" is a different
        // thing to tell the caller than "none of them can read an image".
        if chain.isEmpty {
            throw requireVision ? AIError.noVisionProvider : AIError.noProvidersAvailable
        }

        var lastError: Error?

        // Try each provider in priority order
        for provider in chain {
            do {
                let response = try await callProvider(
                    provider: provider,
                    text: text,
                    ocrText: ocrText,
                    history: history,
                    systemPrompt: systemPrompt,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    imageBase64: imageBase64
                )
                return (response, provider.displayName)
            } catch {
                lastError = error
                print("Provider \(provider.provider) failed: \(error.localizedDescription). Trying next...")
                continue
            }
        }

        throw lastError ?? AIError.noProvidersAvailable
    }

    // MARK: - Worksheet Segmentation

    /// One question per element, in sheet order.
    struct Segmentation {
        let questions: [String]
        /// True when the sheet held more than `maxQuestions`. Not an error —
        /// the first 40 are answered and the student is told.
        let capHit: Bool
    }

    /// Splits a whole extracted worksheet into individual questions.
    ///
    /// Model first, because only a model reliably keeps a sub-part `(a)` with
    /// its parent and knows a table row belongs to the question above it.
    /// Regex second, because a student with no signal still deserves an answer
    /// sheet. The caller sees one list either way and never has to care which
    /// path produced it.
    func segmentQuestions(from text: String) async -> Segmentation {
        let message = Self.segmentPrompt + "\n\nTEXT:\n<<<\n" + text + "\n>>>"

        var parsed: [String]?
        do {
            let (response, _) = try await sendMessage(
                text: message,
                ocrText: nil,
                history: [],
                systemPrompt: Self.segmentPrompt,
                temperature: 0.0,
                maxTokens: 8192
            )
            parsed = WorksheetIntake.parseQuestionArray(response)
        } catch {
            // Every provider in the chain failed. Fall through to the regex.
            parsed = nil
        }

        var questions: [String]
        if let parsed {
            if parsed.isEmpty {
                // The model says there are no questions. Believe it, unless
                // the raw text is plainly numbered — in which case the model,
                // not the file, is what went wrong.
                let pattern = WorksheetIntake.patternSlices(text)
                questions = pattern.count >= 2 ? pattern : []
            } else {
                questions = parsed
            }
        } else {
            questions = WorksheetIntake.patternSlices(text)
        }

        let capHit = questions.count > WorksheetIntake.maxQuestions
        if capHit { questions = Array(questions.prefix(WorksheetIntake.maxQuestions)) }
        return Segmentation(questions: questions, capHit: capHit)
    }

    /// Verbatim on both platforms — a difference here means the two apps split
    /// the same worksheet differently, which is the one divergence a student
    /// would actually notice.
    ///
    /// This prompt is a transcriber, not a translator: the prose it returns keeps
    /// the sheet's own language, and only the maths is forced Latin-inside-
    /// dollars. Only the tutor prompt mandates Arabic *output*, because only the
    /// tutor writes new prose.
    ///
    /// Two clauses here are load-bearing for the review sheet and must not be
    /// softened. Every expression is wrapped in `$…$`, because the card's gate is
    /// `containsMath` and an undelimited element is shown as raw LaTeX source.
    /// The dollars wrap ONE expression, because a span opened before the stem and
    /// closed after the last option makes the whole question one formula and the
    /// option markers become maths-mode italics inside it.
    static let segmentPrompt = """
    You split an exam or homework sheet into its separate questions.

    The text below was extracted from a student's file by OCR, so it may contain
    broken line breaks, page headers, page numbers and stray characters.

    You are splitting, not writing. Copy the text through. Do not answer, do not
    solve, do not translate, do not rephrase, do not reorder, do not correct, and do
    not add a single word that is not in the text below. If the text contains a
    mistake, keep the mistake.

    Return ONLY a JSON array of strings. No prose, no markdown, no code fences, no
    object keys, no trailing text. The first character you output must be [ and the
    last character must be ].

    Each element is one complete question, exactly as it appears in the source, with
    its own numbering removed but with everything it needs to be answerable kept:
    - keep sub-parts such as (a), (b), i, ii inside the same element as their parent
    - keep any given data, table row or figure caption the question depends on
    - keep the prose in its own language: Arabic prose stays Arabic, English prose
      stays English
    - keep the mathematics verbatim: the same numbers, the same signs, the same
      variables, the same order

    MATHEMATICS
    - Write every mathematical expression as LaTeX between single dollar signs, like
      $x^{2} + 1$. Every one of them, however short: a lone variable is $x$, an
      exponent is $n^{2}$, a lone fraction is $\\frac{1}{2}$.
    - The dollars wrap ONE expression. Open them immediately before it and close
      them immediately after it. NEVER open a span before the question stem and
      close it after the last answer option: the stem is its own span, and each
      option is its own span.
    - Inside $...$ everything is Latin script with Western digits 0-9. A sheet that
      prints ٢س + ٣ = ٧ gives the element $2x + 3 = 7$. The renderer cannot read
      Arabic-Indic digits or Arabic letters used as variables, and the student sees
      a red error where the maths should be.
    - Arabic-Indic digits ٠١٢٣٤٥٦٧٨٩ in ordinary prose — a year, a page reference, a
      quantity written in words — stay exactly as written. Only what goes inside the
      dollars is converted.
    - NEVER use \\( \\) or \\[ \\]. They are not rendered and the student sees the raw
      characters instead of the formula.
    - Use proper notation: \\frac{a}{b} not a/b, \\sqrt{x} not sqrt(x), x^{2},
      \\times, \\cdot, \\le, \\ge, \\ne, \\approx, \\infty, \\pi, \\theta, \\int, \\sum, \\lim,
      and \\, before dx.
    - A plain number is not mathematics. Write 20 SAR, not $20$.
    - Escape every backslash, because this is JSON: write \\\\frac, \\\\sqrt, \\\\times. A
      single backslash makes your answer invalid JSON and the student sees nothing.

    ANSWER OPTIONS
    - A multiple-choice question keeps its options in the same element as its stem.
    - Put the stem on the first line and EACH option on its own line, separated by a
      real newline — \\n in the JSON string, never a space, and never a literal
      backslash followed by the letter n typed as two characters.
    - Keep each option's own marker at the start of its line, exactly as the sheet
      prints it: a) b) c) d), or أ) ب) ج) د). The marker is plain text and goes
      OUTSIDE the dollars, like this: a) $\\frac{\\pi}{4}$

    OCR damage is repaired only by joining, never by inventing:
    - a question broken across lines is rejoined into one element
    - a character OCR clearly lost is replaced with three dots, not with a guess
    - a question you cannot make sense of is still returned as it stands; it is the
      student's question, not yours to fix

    NEVER ADD
    - no answers, no results, no worked steps, not even partial ones
    - no hints and no method names
    - no wording of your own such as "Find the value of" unless those words are in
      the text
    - no units, no assumptions, no values you believe were intended
    - no question that is not in the text below

    Drop everything that is not a question: titles, the student or school name,
    "Good luck", instructions such as "Answer all questions", mark allocations in
    brackets, page numbers and running headers.

    If the text contains no questions at all, return exactly [].
    Return at most 40 elements.
    """

    // MARK: - Vision page reading

    /// One call reads a page image and returns its questions, replacing the OCR
    /// stage and the segmentation stage together.
    ///
    /// Verbatim on both platforms, exactly like `segmentPrompt`: a difference
    /// here means the two apps read the same worksheet differently, which is the
    /// one divergence a student would actually notice. Every backslash is
    /// doubled because Swift's multiline literal escapes them; the text that
    /// reaches the model has single backslashes, matching the Kotlin raw string.
    ///
    /// Sent once, as the system instruction only — unlike `segmentPrompt`, which
    /// also rides in the user turn because it had to carry the sheet text
    /// somewhere. Here the payload is the image, so duplicating the prompt would
    /// buy nothing and cost ~550 tokens on every page.
    static let visionPrompt = """
    You are TRANSCRIBING ONE page of a student's exam or homework sheet from the
    image provided, and splitting that page into its separate questions.

    You are a transcriber, not a tutor. Copy what is printed. Do not answer, do not
    solve, do not simplify, do not translate, do not rephrase, do not reorder, do
    not correct, and do not add a single word that is not on the page. If the page
    contains a mistake, transcribe the mistake exactly as printed.

    Return ONLY a JSON array of strings. No prose, no markdown, no code fences, no
    object keys, no trailing text. The first character you output must be [ and the
    last character must be ].

    Each element is one complete question from this page, copied from the image,
    with its own numbering removed but with everything it needs to be answerable
    kept:
    - keep sub-parts such as (a), (b), i, ii inside the same element as their parent
    - keep any given data or table row the question depends on
    - keep the prose in its own language: Arabic prose stays Arabic, English prose
      stays English
    - transcribe handwriting as ordinary text
    - keep the mathematics verbatim: the same numbers, the same signs, the same
      variables, the same order

    MATHEMATICS
    - Write every mathematical expression as LaTeX between single dollar signs, like
      $x^{2} + 1$. Every one of them, however short: a lone variable is $x$, an
      exponent is $n^{2}$, a lone fraction is $\\frac{1}{2}$.
    - The dollars wrap ONE expression. Open them immediately before it and close
      them immediately after it. NEVER open a span before the question stem and
      close it after the last answer option: the stem is its own span, and each
      option is its own span.
    - Inside $...$ everything is Latin script with Western digits 0-9. A page that
      prints ٢س + ٣ = ٧ gives the element $2x + 3 = 7$. The renderer cannot read
      Arabic-Indic digits or Arabic letters used as variables, and the student sees
      a red error where the maths should be.
    - Arabic-Indic digits ٠١٢٣٤٥٦٧٨٩ in ordinary prose — a year, a page reference, a
      quantity written in words — stay exactly as printed. Only what goes inside the
      dollars is converted.
    - NEVER use \\( \\) or \\[ \\]. They are not rendered and the student sees the raw
      characters instead of the formula.
    - Use proper notation: \\frac{a}{b} not a/b, \\sqrt{x} not sqrt(x), x^{2},
      \\times, \\cdot, \\le, \\ge, \\ne, \\approx, \\infty, \\pi, \\theta, \\int, \\sum, \\lim,
      and \\, before dx.
    - A plain number is not mathematics. Write 20 SAR, not $20$.
    - Escape every backslash, because this is JSON: write \\\\frac, \\\\sqrt, \\\\times. A
      single backslash makes your answer invalid JSON and the student sees nothing.

    ANSWER OPTIONS
    - A multiple-choice question keeps its options in the same element as its stem.
    - Put the stem on the first line and EACH option on its own line, separated by a
      real newline — \\n in the JSON string, never a space, and never a literal
      backslash followed by the letter n typed as two characters.
    - Keep each option's own marker at the start of its line, exactly as the page
      prints it: a) b) c) d), or أ) ب) ج) د). The marker is plain text and goes
      OUTSIDE the dollars, like this: a) $\\frac{\\pi}{4}$

    WHEN YOU CANNOT READ SOMETHING
    - Where a character is genuinely unreadable, write three dots and carry on.
      Never guess a digit, a variable, an exponent or a sign.
    - A question you can only partly read is still returned, with three dots where
      the unreadable part was. Do not complete it from what it ought to say.
    - Where a question depends on a diagram, add ONE bracketed sentence describing
      only what is drawn and labelled, in the language of the page, for example
      [Figure: right triangle, legs 3 and 4]. Never state a measurement that is not
      printed on the figure.

    NEVER ADD
    - no answers, no results, no worked steps, not even partial ones
    - no hints, no method names, no "use the chain rule"
    - no wording of your own such as "Find the value of" unless those words are
      printed on the page
    - no units, no assumptions, no values you believe were intended
    - no question that is not on this page

    Drop everything that is not a question: titles, the student or school name, "Good
    luck", instructions such as "Answer all questions", mark allocations in brackets,
    page numbers and running headers.

    If this page holds no questions at all, return exactly [].
    Return at most 40 elements.
    """

    /// Reading is transcription — there is nothing to think about, and 4096
    /// output tokens is generous for one page of questions but not for ten.
    static let visionMaxTokens = 4096

    /// Reads one page image and returns its questions, or `nil` when the reply
    /// was not a JSON array even after the repair in `parseQuestionArray`.
    ///
    /// Throws rather than returning `nil` when the *call* failed, because the
    /// caller's fallback ladder treats "no vision provider", "no network",
    /// "rate limited" and "unparseable" as four different situations.
    func readPage(imageBase64: String, userText: String) async throws -> (questions: [String]?, providerUsed: String) {
        let (response, providerUsed) = try await sendMessage(
            text: userText,
            ocrText: nil,
            history: [],
            systemPrompt: Self.visionPrompt,
            temperature: 0.0,
            maxTokens: Self.visionMaxTokens,
            imageBase64: imageBase64,
            requireVision: true
        )
        return (WorksheetIntake.parseQuestionArray(response), providerUsed)
    }

    // MARK: - Call Provider

    private func callProvider(
        provider: AIProviderConfig,
        text: String,
        ocrText: String?,
        history: [(role: String, content: String)],
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        imageBase64: String? = nil
    ) async throws -> String {

        var userMessage = text
        if let ocr = ocrText, !ocr.isEmpty {
            userMessage = """
            The user sent a photo. Here is the text extracted from it (OCR):
            
            \(ocr)
            
            User's question: \(text)
            """
        }

        switch provider.provider.uppercased() {
        case "GEMINI":
            return try await callGemini(
                provider: provider, message: userMessage, history: history,
                systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens,
                imageBase64: imageBase64)
        case "GROQ", "CEREBRAS", "OPENROUTER", "MISTRAL":
            return try await callOpenAICompatible(
                provider: provider, message: userMessage, history: history,
                systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens,
                imageBase64: imageBase64)
        default:
            throw AIError.unsupportedProvider(provider.provider)
        }
    }

    // MARK: - Gemini API

    private func callGemini(
        provider: AIProviderConfig,
        message: String,
        history: [(role: String, content: String)],
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        imageBase64: String? = nil
    ) async throws -> String {

        let urlString = "\(provider.baseUrl)/models/\(provider.modelName):generateContent?key=\(provider.apiKey)"
        guard let url = URL(string: urlString) else { throw AIError.invalidURL }

        var contents: [[String: Any]] = []
        for msg in history {
            let role = msg.role == "assistant" ? "model" : "user"
            contents.append(["role": role, "parts": [["text": msg.content]]])
        }

        // Image part first, text part second, in the same `parts` array of the
        // same user turn — the order both providers document and the one the
        // OpenAI-compatible builder below mirrors, so the two paths behave the
        // same way. `inlineData` is camelCase to match `systemInstruction` and
        // `maxOutputTokens`; v1beta accepts snake_case too, but mixing the two
        // conventions in one body is how a 400 gets shipped.
        //
        // The array is typed explicitly: left to inference this literal becomes
        // `[[String: String]]` and then refuses the nested dictionary.
        var userParts: [[String: Any]] = []
        if let imageBase64 {
            userParts.append([
                "inlineData": ["mimeType": "image/jpeg", "data": imageBase64]
            ])
        }
        userParts.append(["text": message])
        contents.append(["role": "user", "parts": userParts])

        var generationConfig: [String: Any] = [
            "temperature": temperature,
            "maxOutputTokens": maxTokens
        ]
        // Gemini 2.5 spends output budget on thinking by default and can return
        // a candidate with no `parts` at all — the exact failure `requireContent`
        // exists to catch. Reading a page is transcription with a 4096-token
        // budget that thinking can eat whole, so it is worth switching off there.
        //
        // Gated on the image as well as the slug, because this is the single
        // Gemini builder for every caller: answering a multi-step calculus
        // question is precisely what a dynamic thinking budget is for, and this
        // feature's scope is reading pages, not degrading every chat reply and
        // every worksheet answer in the app.
        //
        // `pro` is excluded on top of that: sending `thinkingConfig` to a non-2.5
        // model is a 400, and Gemini 2.5 Pro rejects a budget of 0 (its minimum
        // is 128) with a 400 as well — so an admin editing `modelName` to
        // `gemini-2.5-pro` on the settings page would otherwise kill the whole
        // Gemini row rather than just slow it down.
        let slug = provider.modelName.lowercased()
        if imageBase64 != nil, slug.contains("2.5"), !slug.contains("pro") {
            generationConfig["thinkingConfig"] = ["thinkingBudget": 0]
        }

        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": [
                "parts": [["text": systemPrompt ?? AIProviderType.gemini.systemPrompt]]
            ],
            "generationConfig": generationConfig
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { throw AIError.networkError }
        if httpResponse.statusCode == 429 { throw AIError.rateLimited(provider.provider) }
        guard httpResponse.statusCode == 200 else { throw AIError.apiError("Status \(httpResponse.statusCode)") }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let candidates = json["candidates"] as? [[String: Any]] ?? []
        let content = candidates.first?["content"] as? [String: Any] ?? [:]
        let parts = content["parts"] as? [[String: Any]] ?? []
        // Every part, not just the first: a reply split across parts would
        // otherwise be silently truncated to its opening fragment.
        let text = parts.compactMap { $0["text"] as? String }.joined()
        return try Self.requireContent(text)
    }

    /// A 200 with nothing usable in it is a failure, not an answer.
    ///
    /// Gemini returns a candidate with no `parts` when the whole token budget
    /// went on thinking (`finishReason: MAX_TOKENS`), and no candidates at all
    /// when the prompt was blocked; OpenAI-compatible providers return a
    /// message with a null `content` in the same situations. Returning a
    /// placeholder string here used to make all of that look like a successful
    /// reply: the batch wrote "No response" into the transcript as the tutor's
    /// answer, the exporter printed it under the problem as if it were the
    /// solution, and — because nothing threw — the question never reached
    /// `failedQuestions`, so the retry affordance could not recover it.
    /// Throwing instead lets the fallback chain try the next provider and, if
    /// they all come back empty, marks the question failed and retryable.
    private static func requireContent(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyResponse
        }
        return text
    }

    // MARK: - OpenAI-Compatible API (Groq, DeepSeek, OpenRouter, Mistral)

    private func callOpenAICompatible(
        provider: AIProviderConfig,
        message: String,
        history: [(role: String, content: String)],
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        imageBase64: String? = nil
    ) async throws -> String {

        let urlString = "\(provider.baseUrl)/chat/completions"
        guard let url = URL(string: urlString) else { throw AIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // OpenRouter serves without it, but free-tier models are deprioritised
        // for callers that do not identify themselves.
        if provider.provider.uppercased() == "OPENROUTER" {
            request.setValue("https://droob-sa.net", forHTTPHeaderField: "HTTP-Referer")
        }

        // `[String: Any]`, not `[String: String]`: a user message carrying an
        // image has an *array* of content parts, which cannot be expressed
        // otherwise. The system message stays a plain string either way.
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt ?? AIProviderType.gemini.systemPrompt]
        ]
        for msg in history {
            messages.append(["role": msg.role, "content": msg.content])
        }
        if let imageBase64 {
            // The `data:` prefix *is* required here — the mirror image of
            // Gemini's bare base64 above.
            let content: [[String: Any]] = [
                ["type": "image_url",
                 "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]],
                ["type": "text", "text": message]
            ]
            messages.append(["role": "user", "content": content])
        } else {
            messages.append(["role": "user", "content": message])
        }

        let body: [String: Any] = [
            "model": provider.modelName,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { throw AIError.networkError }
        if httpResponse.statusCode == 429 { throw AIError.rateLimited(provider.provider) }
        guard httpResponse.statusCode == 200 else { throw AIError.apiError("Status \(httpResponse.statusCode)") }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let choices = json["choices"] as? [[String: Any]] ?? []
        let msg = choices.first?["message"] as? [String: Any] ?? [:]
        return try Self.requireContent(msg["content"] as? String ?? "")
    }

    // MARK: - Errors

    enum AIError: LocalizedError {
        case noProvidersAvailable
        case noVisionProvider
        case unsupportedProvider(String)
        case invalidURL
        case networkError
        case rateLimited(String)
        case apiError(String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "The AI service returned an empty reply."
            case .noVisionProvider:
                return "No AI provider available that can read a page image."
            case .noProvidersAvailable:
                return "No AI providers available. Please try again later."
            case .unsupportedProvider(let name):
                return "Provider \(name) is not supported yet."
            case .invalidURL:
                return "Invalid API URL"
            case .networkError:
                return "Network error. Check your connection."
            case .rateLimited(let provider):
                return "Rate limited by \(provider). Trying next provider..."
            case .apiError(let msg):
                return msg
            }
        }
    }
}
