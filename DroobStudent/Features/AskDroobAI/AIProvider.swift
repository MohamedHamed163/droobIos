import Foundation

/// Supported free AI providers.
/// Each has a free tier with no credit card required.
enum AIProvider: String, CaseIterable, Identifiable {
    case gemini = "gemini"
    case groq = "groq"
    case cerebras = "cerebras"
    case mistral = "mistral"
    case openrouter = "openrouter"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .groq: return "Groq (Fastest)"
        case .cerebras: return "Cerebras (Free)"
        case .mistral: return "Mistral AI"
        case .openrouter: return "OpenRouter"
        }
    }

    var iconName: String {
        switch self {
        case .gemini: return "sparkles"
        case .groq: return "bolt.fill"
        case .cerebras: return "cpu"
        case .mistral: return "wind"
        case .openrouter: return "arrow.triangle.branch"
        }
    }

    /// Base URL for the provider's API.
    var baseURL: String {
        switch self {
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta"
        case .groq:
            return "https://api.groq.com/openai/v1"
        case .cerebras:
            return "https://api.cerebras.ai/v1"
        case .mistral:
            return "https://api.mistral.ai/v1"
        case .openrouter:
            return "https://openrouter.ai/api/v1"
        }
    }

    /// Model name to use for this provider.
    var modelName: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .groq: return "llama-3.3-70b-versatile"
        case .cerebras: return "llama-3.3-70b"
        case .mistral: return "mistral-small-latest"
        case .openrouter: return "google/gemma-3-27b-it:free"
        }
    }

    /// Free tier limits description.
    var freeTierInfo: String {
        switch self {
        case .gemini: return "15 RPM, 1500 RPD"
        case .groq: return "30 RPM, 14400 RPD"
        case .cerebras: return "30 RPM, 1M tokens/day"
        case .mistral: return "30 RPM, 2880 RPD"
        case .openrouter: return "20 RPM, 200 RPD"
        }
    }

    /// The LANGUAGE clause of the system prompt.
    ///
    /// NOTE: this whole file is currently **not compiled** — `AIProvider.swift`
    /// is missing from the target's PBXSourcesBuildPhase, so it has three of
    /// the four project.pbxproj entries a Swift file needs and silently
    /// contributes nothing. The prompt the app actually sends is
    /// `AIProviderType.systemPrompt` in AIProviderManager.swift, which is where
    /// the canonical rule lives. This forwards to it so the two cannot drift if
    /// the file is ever added back to the build.
    ///
    /// "Reply in the language the student wrote in" is not enough for an
    /// Arabic-only app. A formula-only question typed on the maths keyboard, an
    /// English worksheet page, or an OCR read of Latin text all contain no
    /// Arabic at all, so the model answered in English — and that English
    /// answer then became an English exported PDF and an English Library row
    /// title. Under the lock the reply language is stated, not inferred.
    static var languageRule: String { AIProviderType.languageRule }

    /// The tutor persona.
    ///
    /// A forward, not a copy. This file is not compiled (see `languageRule`
    /// above), and while it carried its own literal the two drifted: the live
    /// prompt gained the Arabic-only lock and the Latin-maths rule while this one
    /// still asked for English step labels. One prompt, one place — whatever
    /// `AIProviderType` sends is what this returns, so the pair cannot drift
    /// again if the file is ever added to the build.
    var systemPrompt: String { AIProviderType.gemini.systemPrompt }
}

/// API key storage (in production, fetch from backend on login).
/// For now, stored locally — replace with your own keys.
struct AIKeys {
    static func apiKey(for provider: AIProvider) -> String? {
        // TODO: Replace these with your actual API keys
        // Get free keys from:
        // Gemini: https://aistudio.google.com/apikey
        // Groq: https://console.groq.com/keys
        // Cerebras: https://cloud.cerebras.ai
        // Mistral: https://console.mistral.ai/api-keys
        // OpenRouter: https://openrouter.ai/keys

        switch provider {
        case .gemini:
            return UserDefaults.standard.string(forKey: "ai_key_gemini")
        case .groq:
            return UserDefaults.standard.string(forKey: "ai_key_groq")
        case .cerebras:
            return UserDefaults.standard.string(forKey: "ai_key_cerebras")
        case .mistral:
            return UserDefaults.standard.string(forKey: "ai_key_mistral")
        case .openrouter:
            return UserDefaults.standard.string(forKey: "ai_key_openrouter")
        }
    }

    static func setKey(_ key: String, for provider: AIProvider) {
        let keyName = "ai_key_\(provider.rawValue)"
        UserDefaults.standard.set(key, forKey: keyName)
    }
}
