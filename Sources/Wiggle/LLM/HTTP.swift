import Foundation

enum HTTP {
    static func jsonRequest(_ url: URL, method: String = "POST", body: Any? = nil, headers: [String: String] = [:]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    /// Starts a streaming request and returns its lines, throwing the server's own
    /// error message for non-2xx responses.
    static func lines(for request: URLRequest) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 64_000 { break }
            }
            throw LLMError.server(errorMessage(from: body) ?? "Request failed with HTTP \(status).")
        }
        return bytes.lines
    }

    /// Extracts `{"error": {"message": …}}` (Anthropic, OpenAI) or `{"error": "…"}` (Ollama).
    static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return json["error"] as? String
    }

    /// Server-sent events: returns the JSON payload of a `data:` line, if any.
    static func sseData(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }
}
