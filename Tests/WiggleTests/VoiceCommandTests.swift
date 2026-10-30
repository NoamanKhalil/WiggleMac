import Testing
@testable import Wiggle

struct VoiceCommandTests {
    @Test(arguments: [
        ("Screenshot", ""),
        ("screenshot.", ""),
        ("Take a screenshot", ""),
        ("Take a screenshot and tell me what this error means", "Tell me what this error means"),
        ("screen shot what's on my screen?", "What's on my screen?"),
        ("Capture my screen, then summarize it", "Then summarize it"),
        ("What does this chart show? Screenshot", "What does this chart show?"),
    ])
    func detectsScreenshotRequests(utterance: String, question: String) {
        let parsed = VoiceCommand.parse(utterance)
        #expect(parsed.wantsScreenshot)
        #expect(parsed.question == question)
    }

    @Test func plainQuestionPassesThrough() {
        let parsed = VoiceCommand.parse("  What's the capital of France? ")
        #expect(parsed == .init(wantsScreenshot: false, question: "What's the capital of France?"))
    }

    @Test func screenAloneIsNotACommand() {
        #expect(!VoiceCommand.parse("How do I clean my screen").wantsScreenshot)
    }
}
