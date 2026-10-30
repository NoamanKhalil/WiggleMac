import AppKit
import Foundation
import Testing
@testable import Wiggle

/// Talks to real local models. Run with: WIGGLE_INTEGRATION=1 swift test --filter IntegrationTests
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WIGGLE_INTEGRATION"] == "1"))
struct IntegrationTests {
    /// A fake "screenshot": white canvas with an error message drawn on it.
    private func fakeScreenshot(text: String) -> Screenshot {
        let image = NSImage(size: NSSize(width: 900, height: 300), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            (text as NSString).draw(at: NSPoint(x: 40, y: 130), withAttributes: [
                .font: NSFont.systemFont(ofSize: 40, weight: .bold),
                .foregroundColor: NSColor.black,
            ])
            return true
        }
        return Screenshot(original: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    }

    private func reply(_ session: ChatSession, _ prompt: String, screenshot: Screenshot? = nil) async throws -> String {
        var last = ""
        for try await text in session.send(prompt, screenshot: screenshot) { last = text }
        return last
    }

    @Test func ocrReadsScreenshotText() async {
        let text = await fakeScreenshot(text: "Error 404: Page not found").recognizedText()
        #expect(text.contains("404"))
    }

    @Test func qwenAnswersAndRemembers() async throws {
        let session = OllamaChatSession(client: OllamaClient(host: URL(string: "http://localhost:11434")!), model: "qwen2.5:0.5b")
        let first = try await reply(session, "My name is Noa. Reply with just: OK")
        #expect(!first.isEmpty)
        let second = try await reply(session, "What is my name? One word.")
        #expect(second.localizedCaseInsensitiveContains("Noa"))
    }

    @Test func qwenReadsScreenshotViaOCR() async throws {
        let session = OllamaChatSession(client: OllamaClient(host: URL(string: "http://localhost:11434")!), model: "qwen2.5:0.5b")
        let answer = try await reply(session, "What error code is shown? Reply with just the number.",
                                     screenshot: fakeScreenshot(text: "Error 404: Page not found"))
        #expect(answer.contains("404"))
    }

    @Test func missingOllamaModelExplainsHowToGetIt() async throws {
        let session = OllamaChatSession(client: OllamaClient(host: URL(string: "http://localhost:11434")!), model: "not-a-real-model:1b")
        await #expect(throws: LLMError.self) { _ = try await reply(session, "hi") }
    }

    @Test func appleModelSeesScreenshot() async throws {
        try #require(AppleChatSession.unavailableReason == nil)
        let session = AppleChatSession()
        let answer = try await reply(session, "What error code is shown in this screenshot? Reply with just the number.",
                                     screenshot: fakeScreenshot(text: "Error 404: Page not found"))
        #expect(answer.contains("404"))
    }
}
