import Foundation
import FoundationModels

/// Apple's on-device foundation model (Apple Intelligence).
@MainActor
final class AppleChatSession: ChatSession {
    let modelName = "Apple Intelligence"

    private let session = LanguageModelSession(instructions: Prompts.system)

    /// nil when the on-device model is ready to use.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in System Settings to use the on-device model."
            case .modelNotReady:
                return "The Apple Intelligence model is still downloading. Try again shortly."
            @unknown default:
                return "Apple Intelligence is unavailable."
            }
        }
    }

    func send(_ prompt: String, screenshot: Screenshot?) -> AsyncThrowingStream<String, Error> {
        makeTextStream { yield in
            do {
                for try await snapshot in try await self.responseStream(prompt, screenshot: screenshot) {
                    yield(snapshot.content)
                }
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                throw LLMError.server("This conversation is too long for the on-device model. Close it and wiggle to start fresh.")
            }
        }
    }

    private func responseStream(_ prompt: String, screenshot: Screenshot?) async throws -> LanguageModelSession.ResponseStream<String> {
        guard let screenshot else {
            return session.streamResponse(to: prompt)
        }
        if #available(macOS 27, *), SystemLanguageModel.default.capabilities.contains(.vision) {
            return session.streamResponse(to: Prompt { prompt; Attachment(screenshot.image) })
        }
        let text = await screenshot.recognizedText()
        return session.streamResponse(to: Prompts.withScreenText(text, question: prompt))
    }
}
