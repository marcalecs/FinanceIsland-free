import Foundation
import Security

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case off, pollinations, ollama, groq, gemini, openrouter
    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: return "Built-in (no AI)"
        case .pollinations: return "Pollinations"
        case .ollama: return "Ollama"
        case .groq: return "Groq"
        case .gemini: return "Google Gemini"
        case .openrouter: return "OpenRouter"
        }
    }

    var note: String {
        switch self {
        case .off: return "Headline keywords + the signal. Nothing leaves your Mac except the news request."
        case .pollinations: return "Free, no account or key. Community service: requests are anonymous but go to pollinations.ai."
        case .ollama: return "Free and private: the model runs on your Mac. Install from ollama.com, then run: ollama pull llama3.2"
        case .groq: return "Free tier with a key from console.groq.com. Very fast."
        case .gemini: return "Free tier with a key from aistudio.google.com."
        case .openrouter: return "Free models with a key from openrouter.ai."
        }
    }

    var endpoint: URL? {
        switch self {
        case .off: return nil
        case .pollinations: return URL(string: "https://text.pollinations.ai/openai")
        case .ollama: return URL(string: "http://localhost:11434/v1/chat/completions")
        case .groq: return URL(string: "https://api.groq.com/openai/v1/chat/completions")
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        case .openrouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")
        }
    }

    var defaultModel: String {
        switch self {
        case .off: return ""
        case .pollinations: return "openai"
        case .ollama: return "llama3.2"
        case .groq: return "llama-3.3-70b-versatile"
        case .gemini: return "gemini-2.5-flash"
        case .openrouter: return "meta-llama/llama-3.3-70b-instruct:free"
        }
    }

    var needsKey: Bool { [.groq, .gemini, .openrouter].contains(self) }
}

enum AIError: LocalizedError {
    case notConfigured, missingKey, http(Int, String), empty

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "No AI provider selected"
        case .missingKey: return "Add an API key in Settings ▸ Assistant"
        case .http(let code, let body): return "AI service answered \(code)" + (body.isEmpty ? "" : ": " + body.prefix(120))
        case .empty: return "The AI returned an empty answer"
        }
    }
}

enum AIClient {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 90
        return URLSession(configuration: c)
    }()

    static func complete(provider: AIProvider, model: String, key: String?,
                         system: String, user: String) async throws -> String {
        guard let url = provider.endpoint else { throw AIError.notConfigured }
        if provider.needsKey && (key ?? "").isEmpty { throw AIError.missingKey }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty { req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        if provider == .openrouter {
            req.setValue("FinanceIsland", forHTTPHeaderField: "X-Title")
        }
        var body: [String: Any] = [
            "model": model.isEmpty ? provider.defaultModel : model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "temperature": 0.2,
        ]
        if provider == .pollinations { body["private"] = true }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw AIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw AIError.empty }
        return content
    }
}

enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "FinanceIsland.ai",
         kSecAttrAccount as String: account]
    }

    static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ account: String, _ value: String?) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func eraseAll() {
        for p in AIProvider.allCases { set(p.rawValue, nil) }
    }
}
