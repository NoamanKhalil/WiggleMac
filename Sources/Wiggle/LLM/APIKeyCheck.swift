import Foundation

/// Checks an API key before it's saved: common paste mistakes first, then a free request that lists
/// the provider's models, which needs a working key and costs nothing.
enum APIKeyCheck {
    enum Provider: String {
        case anthropic = "Anthropic"
        case openai = "OpenAI"
    }

    enum Result: Equatable {
        case valid
        case invalid(String)
        /// The key looks right but couldn't be checked (offline, or the provider is down).
        case unverified(String)
    }

    static func check(_ key: String, for provider: Provider) async -> Result {
        if let problem = formatProblem(key, for: provider) { return .invalid(problem) }
        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200..<300:
                return .valid
            case 401, 403:
                let detail = HTTP.errorMessage(from: data).map { " (\($0))" } ?? ""
                return .invalid("\(provider.rawValue) didn't accept this key\(detail).")
            default:
                return .unverified("Couldn't check the key: \(provider.rawValue) answered with HTTP \(status).")
            }
        } catch {
            return .unverified("Couldn't reach \(provider.rawValue) to check the key: \(error.localizedDescription)")
        }
    }

    /// Mistakes visible in the key itself, worded so they can be fixed.
    static func formatProblem(_ key: String, for provider: Provider) -> String? {
        if key.isEmpty { return "Paste a key first." }
        if key.contains(where: \.isWhitespace) { return "The key has spaces or line breaks in it. Copy it again from the console." }
        switch provider {
        case .anthropic:
            if key.hasPrefix("sk-ant-admin") {
                return "That's an Admin key. Create a regular API key under Settings → API Keys at console.anthropic.com."
            }
            if !key.hasPrefix("sk-ant-") {
                return "Anthropic API keys start with “sk-ant-”. Copy the key from console.anthropic.com → Settings → API Keys."
            }
        case .openai:
            if key.hasPrefix("sk-ant-") { return "That's an Anthropic key. Paste it in the Claude section instead." }
            if !key.hasPrefix("sk-") { return "OpenAI API keys start with “sk-”." }
        }
        return nil
    }
}
