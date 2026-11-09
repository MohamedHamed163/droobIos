import Foundation
import SwiftUI

/// Free AI service that supports multiple providers.
/// No backend calls — phone communicates directly with free AI APIs.
struct FreeAIService {

    /// Send a chat message to the selected AI provider.
    /// Supports text-only and image + text (photo OCR results).
    static func sendMessage(
        text: String,
        ocrText: String? = nil,
        provider: AIProvider,
        history: [(role: String, content: String)] = []
    ) async throws -> String {

        guard let apiKey = AIKeys.apiKey(for: provider), !apiKey.isEmpty else {
            throw AIError.noAPIKey(provider)
        }

        // Build the user message with optional OCR text
        var userMessage = text
        if let ocr = ocrText, !ocr.isEmpty {
            userMessage = """
            The user sent a photo. Here is the text extracted from it (OCR):
            
            \(ocr)
            
            User's question: \(text)
            """
        }

        switch provider {
        case .gemini:
            return try await callGemini(
                message: userMessage,
                apiKey: apiKey,
                history: history
            )
        case .groq:
            return try await callOpenAICompatible(
                message: userMessage,
                apiKey: apiKey,
                baseURL: "https://api.groq.com/openai/v1",
                model: "llama-3.3-70b-versatile",
                history: history
            )
        case .deepseek:
            return try await callOpenAICompatible(
                message: userMessage,
                apiKey: apiKey,
                baseURL: "https://api.deepseek.com",
                model: "deepseek-chat",
                history: history
            )
        case .openrouter:
            return try await callOpenAICompatible(
                message: userMessage,
                apiKey: apiKey,
                baseURL: "https://openrouter.ai/api/v1",
                model: "meta-llama/llama-3.3-70b-instruct:free",
                history: history,
                extraHeaders: ["HTTP-Referer": "https://droob-sa.net"]
            )
        case .cloudflare:
            return try await callCloudflareAI(
                message: userMessage,
                apiKey: apiKey,
                history: history
            )
        case .huggingface:
            return try await callHuggingFace(
                message: userMessage,
                apiKey: apiKey,
                history: history
            )
        }
    }

    // MARK: - Gemini (Google)

    private static func callGemini(
        message: String,
        apiKey: String,
        history: [(role: String, content: String)]
    ) async throws -> String {

        let model = "gemini-2.5-flash"
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw AIError.invalidURL
        }

        // Build contents array with history
        var contents: [[String: Any]] = []

        for msg in history {
            let role = msg.role == "assistant" ? "model" : "user"
            contents.append([
                "role": role,
                "parts": [["text": msg.content]]
            ])
        }

        // Add current message
        contents.append([
            "role": "user",
            "parts": [["text": message]]
        ])

        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": [
                "parts": [["text": AIProvider.gemini.systemPrompt]]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048
            ]
        ]

        return try await performRequest(url: url, body: body) { json in
            let candidates = json["candidates"] as? [[String: Any]] ?? []
            let first = candidates.first ?? [:]
            let content = first["content"] as? [String: Any] ?? [:]
            let parts = content["parts"] as? [[String: Any]] ?? []
            return parts.first?["text"] as? String ?? "No response"
        }
    }

    // MARK: - OpenAI-Compatible (Groq, DeepSeek, OpenRouter)

    private static func callOpenAICompatible(
        message: String,
        apiKey: String,
        baseURL: String,
        model: String,
        history: [(role: String, content: String)],
        extraHeaders: [String: String] = [:]
    ) async throws -> String {

        let urlString = "\(baseURL)/chat/completions"
        guard let url = URL(string: urlString) else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Build messages array
        var messages: [[String: String]] = [
            ["role": "system", "content": AIProvider.gemini.systemPrompt]
        ]

        for msg in history {
            messages.append(["role": msg.role, "content": msg.content])
        }

        messages.append(["role": "user", "content": message])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 2048
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError.apiError("Request failed with status \(statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let choices = json["choices"] as? [[String: Any]] ?? []
        let first = choices.first ?? [:]
        let msg = first["message"] as? [String: Any] ?? [:]
        return msg["content"] as? String ?? "No response"
    }

    // MARK: - Cloudflare Workers AI

    private static func callCloudflareAI(
        message: String,
        apiKey: String,
        history: [(role: String, content: String)]
    ) async throws -> String {

        // Cloudflare requires account ID — user must configure this
        guard let accountID = UserDefaults.standard.string(forKey: "cloudflare_account_id") else {
            throw AIError.apiError("Cloudflare account ID not configured")
        }

        let model = "@cf/meta/llama-3.3-70b-instruct-fp16"
        let urlString = "https://api.cloudflare.com/client/v4/accounts/\(accountID)/ai/run/\(model)"

        guard let url = URL(string: urlString) else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var messages: [[String: String]] = [
            ["role": "system", "content": AIProvider.cloudflare.systemPrompt]
        ]
        for msg in history {
            messages.append(["role": msg.role, "content": msg.content])
        }
        messages.append(["role": "user", "content": message])

        let body: [String: Any] = [
            "messages": messages,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let result = json["result"] as? [String: Any] ?? [:]
        return result["response"] as? String ?? "No response"
    }

    // MARK: - Hugging Face

    private static func callHuggingFace(
        message: String,
        apiKey: String,
        history: [(role: String, content: String)]
    ) async throws -> String {

        let model = "meta-llama/Llama-3.3-70B-Instruct"
        let urlString = "https://api-inference.huggingface.co/models/\(model)"

        guard let url = URL(string: urlString) else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var messages: [[String: String]] = [
            ["role": "system", "content": AIProvider.huggingface.systemPrompt]
        ]
        for msg in history {
            messages.append(["role": msg.role, "content": msg.content])
        }
        messages.append(["role": "user", "content": message])

        let body: [String: Any] = [
            "inputs": messages,
            "parameters": [
                "max_new_tokens": 2048,
                "temperature": 0.7
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIError.apiError("HuggingFace request failed")
        }

        // HF returns array of generated text
        let json = try JSONSerialization.jsonObject(with: data)
        if let arr = json as? [[String: Any]], let first = arr.first {
            return first["generated_text"] as? String ?? "No response"
        }
        return "No response"
    }

    // MARK: - Helpers

    private static func performRequest(
        url: URL,
        body: [String: Any],
        parseResponse: ([String: Any]) -> String?
    ) async throws -> String {

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError.apiError("Request failed with status \(statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        if let text = parseResponse(json) {
            return text
        }

        throw AIError.parseError
    }

    // MARK: - Errors

    enum AIError: LocalizedError {
        case noAPIKey(AIProvider)
        case invalidURL
        case apiError(String)
        case parseError

        var errorDescription: String? {
            switch self {
            case .noAPIKey(let provider):
                return "No API key configured for \(provider.displayName). Go to Settings > AI to add one."
            case .invalidURL:
                return "Invalid API URL"
            case .apiError(let message):
                return message
            case .parseError:
                return "Could not parse AI response"
            }
        }
    }
}
