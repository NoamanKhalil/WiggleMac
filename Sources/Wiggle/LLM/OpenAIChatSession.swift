import Foundation

/// OpenAI's Chat Completions API, with the user's own API key.
@MainActor
final class OpenAIChatSession: ChatSession {
    let modelName: String

    private let apiKey: String
    private let model: String
    private var messages: [[String: Any]] = [["role": "system", "content": Prompts.system]]

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
        self.modelName = "OpenAI \(model)"
    }

    func send(_ prompt: String, screenshot: Screenshot?) -> AsyncThrowingStream<String, Error> {
        makeTextStream { yield in
            var content: [[String: Any]] = [["type": "text", "text": prompt]]
            if let screenshot {
                content.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(screenshot.base64JPEG)"],
                ])
            }
            self.messages.append(["role": "user", "content": content])

            do {
                let reply = try await self.stream(onText: yield)
                self.messages.append(["role": "assistant", "content": reply])
            } catch {
                self.messages.removeLast()
                throw error
            }
        }
    }

    private func stream(onText: (String) -> Void) async throws -> String {
        let request = try HTTP.jsonRequest(
            URL(string: "https://api.openai.com/v1/chat/completions")!,
            body: ["model": model, "messages": messages, "stream": true],
            headers: ["Authorization": "Bearer \(apiKey)"]
        )
        var text = ""
        do {
            for try await line in try await HTTP.lines(for: request) {
                guard let payload = HTTP.sseData(line), payload != "[DONE]",
                      let chunk = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
                else { continue }
                if let error = chunk["error"] as? [String: Any] {
                    throw LLMError.server(error["message"] as? String ?? "OpenAI returned an error.")
                }
                let choice = (chunk["choices"] as? [[String: Any]])?.first
                if let piece = (choice?["delta"] as? [String: Any])?["content"] as? String {
                    text += piece
                    onText(text)
                }
            }
        } catch LLMError.server(let message) where message.contains("API key") {
            throw LLMError.unavailable("Your OpenAI API key was rejected. Update it in Models….")
        }
        return text
    }
}
