import Foundation

/// A multi-turn conversation with a model. `send` streams the reply as
/// cumulative text: each element is the full response so far.
@MainActor
protocol ChatSession: AnyObject {
    var modelName: String { get }
    func send(_ prompt: String, screenshot: Screenshot?) -> AsyncThrowingStream<String, Error>
}

enum LLMError: LocalizedError {
    case unavailable(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .server(let message): message
        }
    }
}

enum Prompts {
    static let system = """
        You are Wiggle, a quick assistant that pops up next to the user's cursor on their Mac. \
        Answer concisely and directly. Prefer short paragraphs or brief lists. \
        Use plain text unless formatting clearly helps. \
        When the user shares a screenshot, it shows their whole screen; focus on what their question is about.
        """

    static let describeScreen = "What's on my screen?"

    /// For models that can't take images: the question plus text recognized in the screenshot.
    static func withScreenText(_ text: String, question: String) -> String {
        let screenText = text.isEmpty ? "(no readable text found)" : text
        return """
            I'm sharing a screenshot of my screen. You can't see images, so here is the text recognized in it:

            <screen_text>
            \(screenText)
            </screen_text>

            \(question)
            """
    }
}

@MainActor
enum LLM {
    static func makeSession(for choice: ModelChoice, settings: Settings = .shared) throws -> ChatSession {
        switch choice {
        case .apple:
            if let reason = AppleChatSession.unavailableReason {
                throw LLMError.unavailable(reason)
            }
            return AppleChatSession()
        case .ollama(let model):
            return OllamaChatSession(client: OllamaClient(host: settings.ollamaHost), model: model)
        case .anthropic(let model):
            guard let key = Keychain.read(.anthropic) else {
                throw LLMError.unavailable("Add your Anthropic API key in Models… to use Claude.")
            }
            return AnthropicChatSession(apiKey: key, model: model)
        case .openai(let model):
            guard let key = Keychain.read(.openai) else {
                throw LLMError.unavailable("Add your OpenAI API key in Models… to use OpenAI.")
            }
            return OpenAIChatSession(apiKey: key, model: model)
        }
    }
}

/// Runs `body` on the main actor and exposes what it yields as a stream; cancelling the
/// consumer cancels the work.
@MainActor
func makeTextStream(
    _ body: @escaping @MainActor (_ yield: (String) -> Void) async throws -> Void
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task { @MainActor in
            do {
                try await body { continuation.yield($0) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
