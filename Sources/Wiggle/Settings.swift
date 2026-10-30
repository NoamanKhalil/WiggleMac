import Foundation

/// Which model answers. Stored as "provider:model", e.g. "ollama:qwen2.5:0.5b".
enum ModelChoice: Hashable, Sendable {
    case apple
    case ollama(String)
    case anthropic(String)
    case openai(String)

    init?(storageValue: String) {
        let provider = storageValue.prefix { $0 != ":" }
        let model = String(storageValue.dropFirst(provider.count + 1))
        switch provider {
        case "apple": self = .apple
        case "ollama" where !model.isEmpty: self = .ollama(model)
        case "anthropic" where !model.isEmpty: self = .anthropic(model)
        case "openai" where !model.isEmpty: self = .openai(model)
        default: return nil
        }
    }

    var storageValue: String {
        switch self {
        case .apple: "apple"
        case .ollama(let model): "ollama:\(model)"
        case .anthropic(let model): "anthropic:\(model)"
        case .openai(let model): "openai:\(model)"
        }
    }

    var displayName: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .ollama(let model): model
        case .anthropic(let model): AnthropicChatSession.displayName(for: model)
        case .openai(let model): "OpenAI \(model)"
        }
    }
}

enum Sensitivity: String, CaseIterable, Sendable {
    case low
    case medium
    case high

    var title: String { rawValue.capitalized }

    /// Direction reversals needed inside the detection window.
    var requiredReversals: Int {
        switch self {
        case .low: 6
        case .medium: 5
        case .high: 4
        }
    }

    /// Minimum travel (in points) between reversals for a stroke to count.
    var minStroke: Double {
        switch self {
        case .low: 60
        case .medium: 40
        case .high: 25
        }
    }
}

/// UserDefaults-backed preferences. API keys live in the Keychain, not here.
@MainActor
final class Settings {
    static let shared = Settings()

    static let defaultOllamaModel = "qwen2.5:0.5b"

    private let defaults = UserDefaults.standard

    var isEnabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    /// The chosen model. Defaults to Apple Intelligence when it's ready, else a small Qwen via Ollama.
    var model: ModelChoice {
        get {
            if let stored = defaults.string(forKey: "model"), let choice = ModelChoice(storageValue: stored) {
                return choice
            }
            return AppleChatSession.unavailableReason == nil ? .apple : .ollama(Self.defaultOllamaModel)
        }
        set { defaults.set(newValue.storageValue, forKey: "model") }
    }

    var sensitivity: Sensitivity {
        get { Sensitivity(rawValue: defaults.string(forKey: "sensitivity") ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "sensitivity") }
    }

    var ollamaHost: URL {
        get { defaults.url(forKey: "ollamaHost") ?? URL(string: "http://localhost:11434")! }
        set { defaults.set(newValue, forKey: "ollamaHost") }
    }

    var anthropicModel: String {
        get { defaults.string(forKey: "anthropicModel") ?? AnthropicChatSession.models[0].id }
        set { defaults.set(newValue, forKey: "anthropicModel") }
    }

    var openAIModel: String {
        get { defaults.string(forKey: "openAIModel") ?? "gpt-5-mini" }
        set { defaults.set(newValue, forKey: "openAIModel") }
    }
}
