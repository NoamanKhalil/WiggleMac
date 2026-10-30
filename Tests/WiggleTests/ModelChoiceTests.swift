import Testing
@testable import Wiggle

struct ModelChoiceTests {
    @Test(arguments: [
        ModelChoice.apple,
        .ollama("qwen2.5:0.5b"),
        .ollama("moondream"),
        .anthropic("claude-opus-5-5"),
        .openai("gpt-5-mini"),
    ])
    func roundTrips(choice: ModelChoice) {
        #expect(ModelChoice(storageValue: choice.storageValue) == choice)
    }

    @Test func ollamaNamesKeepTheirTag() {
        #expect(ModelChoice(storageValue: "ollama:qwen3-vl:2b") == .ollama("qwen3-vl:2b"))
    }

    @Test(arguments: ["", "ollama:", "unknown:model", "anthropic"])
    func rejectsInvalidValues(value: String) {
        #expect(ModelChoice(storageValue: value) == nil)
    }
}
