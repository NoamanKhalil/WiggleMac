import Foundation

/// A local model served by Ollama (e.g. `qwen2.5:0.5b`) over its /api/chat endpoint.
@MainActor
final class OllamaChatSession: ChatSession {
    let modelName: String

    private let client: OllamaClient
    private var messages: [Message]
    private var supportsVision: Bool?

    init(client: OllamaClient, model: String) {
        self.client = client
        self.modelName = model
        self.messages = [Message(role: "system", content: Prompts.system)]
    }

    func send(_ prompt: String, screenshot: Screenshot?) -> AsyncThrowingStream<String, Error> {
        makeTextStream { yield in
            let message = await self.userMessage(prompt, screenshot: screenshot)
            self.messages.append(message)
            do {
                let reply = try await self.streamChat(onText: yield)
                self.messages.append(Message(role: "assistant", content: reply))
            } catch {
                self.messages.removeLast()
                throw self.friendlyError(error)
            }
        }
    }

    /// Vision models get the image itself; text-only models get the text recognized in it.
    private func userMessage(_ prompt: String, screenshot: Screenshot?) async -> Message {
        guard let screenshot else {
            return Message(role: "user", content: prompt)
        }
        if supportsVision == nil {
            let installed = try? await client.installedModels()
            supportsVision = installed?.first { $0.name == modelName || $0.name == "\(modelName):latest" }?.supportsVision ?? false
        }
        if supportsVision == true {
            return Message(role: "user", content: prompt, images: [screenshot.base64JPEG])
        }
        let text = await screenshot.recognizedText()
        return Message(role: "user", content: Prompts.withScreenText(text, question: prompt))
    }

    private func streamChat(onText: (String) -> Void) async throws -> String {
        let body = ChatRequest(model: modelName, messages: messages, stream: true)
        var request = URLRequest(url: client.host.appending(path: "api/chat"))
        // Loading a model the first time can take well over a minute before the first token.
        request.timeoutInterval = 300
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        var text = ""
        for try await line in try await HTTP.lines(for: request) {
            let chunk = try JSONDecoder().decode(ChatChunk.self, from: Data(line.utf8))
            if let error = chunk.error {
                throw LLMError.server(error)
            }
            text += chunk.message?.content ?? ""
            onText(text)
            if chunk.done == true { break }
        }
        return text
    }

    private func friendlyError(_ error: Error) -> Error {
        if let urlError = error as? URLError,
           [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost].contains(urlError.code) {
            return LLMError.unavailable("Can't reach Ollama at \(client.host.absoluteString). Open the Ollama app or run `ollama serve`.")
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return LLMError.unavailable("\(modelName) took too long to answer. Try again, or pick a smaller model in Models….")
        }
        if case LLMError.server(let message) = error, message.contains("not found") {
            return LLMError.unavailable("\(modelName) isn't downloaded yet. Get it from Models… in the menu bar.")
        }
        return error
    }
}

private struct Message: Codable {
    let role: String
    let content: String
    var images: [String]? = nil
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool
}

private struct ChatChunk: Decodable {
    let message: Message?
    let done: Bool?
    let error: String?
}
