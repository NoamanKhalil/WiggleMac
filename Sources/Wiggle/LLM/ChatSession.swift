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

    /// A request to change a workflow, with its steps numbered as `WorkflowEdits` counts them.
    static func editWorkflow(_ workflow: Workflow, request: String) -> String {
        let groups = WorkflowStepGroup.groups(for: workflow.steps)
        let outline = groups.enumerated().map { index, group in
            if let text = group.text { "\(index + 1). Type \(quoted(text))" } else { "\(index + 1). \(group.title)" }
        }
        let typing = groups.indices.filter { groups[$0].text != nil }.map { String($0 + 1) }
        return """
            I'm changing a Wiggle workflow named "\(workflow.name)". It replays my recorded clicks and typing \
            at the same spots on screen. Its steps:

            <workflow>
            \(outline.joined(separator: "\n"))
            </workflow>

            You can change what a Type step types, or remove steps. You can't add, move or change clicks. \
            For each change, put one of these in your reply:
            <type step="N">the complete new text for step N</type>
            <remove steps="N"/> or <remove steps="N-M"/>

            Only steps \(typing.joined(separator: ", ")) type anything, so only those can have a <type> tag. Line breaks inside <type> are typed with Shift-Return. Write new text the way I write: match the \
            tone, punctuation and length of what the step types now. Never leave placeholders like [Name]; \
            if you need something I haven't told you, ask instead of guessing. Change only what I ask for, \
            and keep anything else you say to a sentence or two, outside the tags.

            \(request)
            """
    }

    /// `text` in double quotes, with line breaks and quotes escaped so each step stays on one line.
    private static func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

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
                throw LLMError.unavailable("Add your Anthropic API key in Settings → Models to use Claude.")
            }
            return AnthropicChatSession(apiKey: key, model: model)
        case .openai(let model):
            guard let key = Keychain.read(.openai) else {
                throw LLMError.unavailable("Add your OpenAI API key in Settings → Models to use OpenAI.")
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
