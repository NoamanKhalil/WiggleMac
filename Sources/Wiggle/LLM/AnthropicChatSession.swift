import Foundation

/// Claude through the Anthropic Messages API, with the user's own API key.
@MainActor
final class AnthropicChatSession: ChatSession {
    struct Model: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
    }

    nonisolated static let models = [
        Model(id: "claude-opus-5-5", name: "Claude Opus 5.5"),
        Model(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5"),
        Model(id: "claude-haiku-4-5", name: "Claude Haiku 4.5"),
    ]

    nonisolated static func displayName(for id: String) -> String {
        models.first { $0.id == id }?.name ?? id
    }

    let modelName: String

    private let apiKey: String
    private let model: String
    /// Full message history. Assistant turns keep every content block exactly as
    /// received (including thinking blocks and their signatures), as the API requires.
    private var messages: [[String: Any]] = []

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
        self.modelName = Self.displayName(for: model)
    }

    func send(_ prompt: String, screenshot: Screenshot?) -> AsyncThrowingStream<String, Error> {
        makeTextStream { yield in
            var content: [[String: Any]] = []
            if let screenshot {
                content.append([
                    "type": "image",
                    "source": ["type": "base64", "media_type": "image/jpeg", "data": screenshot.base64JPEG],
                ])
            }
            content.append(["type": "text", "text": prompt])
            self.messages.append(["role": "user", "content": content])

            do {
                let blocks = try await self.stream(onText: yield)
                self.messages.append(["role": "assistant", "content": blocks])
            } catch {
                self.messages.removeLast()
                throw error
            }
        }
    }

    private func stream(onText: (String) -> Void) async throws -> [[String: Any]] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 64000,
            "stream": true,
            "system": Prompts.system,
            "messages": messages,
        ]
        var headers = [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
        ]
        // Haiku 4.5 takes neither effort nor server-side fallbacks.
        if model != "claude-haiku-4-5" {
            // A pop-up assistant favors fast replies.
            body["output_config"] = ["effort": "low"]
            // If a safety classifier declines, the API retries on its recommended fallback model.
            body["fallbacks"] = "default"
            headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
        }

        let request = try HTTP.jsonRequest(
            URL(string: "https://api.anthropic.com/v1/messages")!, body: body, headers: headers
        )
        var accumulator = AnthropicStreamAccumulator()
        do {
            for try await line in try await HTTP.lines(for: request) {
                guard let payload = HTTP.sseData(line),
                      let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
                else { continue }
                if try accumulator.apply(event) {
                    onText(accumulator.visibleText)
                }
            }
        } catch LLMError.server(let message) where message.contains("x-api-key") || message.contains("authentication") {
            throw LLMError.unavailable("Your Anthropic API key was rejected. Update it in Models….")
        }

        if accumulator.stopReason == "refusal" {
            throw LLMError.server("Claude declined to answer this request.")
        }
        return accumulator.blocks
    }
}

/// Rebuilds the assistant message from Messages API stream events.
struct AnthropicStreamAccumulator {
    private(set) var blocks: [[String: Any]] = []
    private(set) var stopReason: String?

    /// Text from the reply's text blocks. If the API switched to a fallback model
    /// mid-reply, only the text after the switch.
    var visibleText: String {
        let start = (blocks.lastIndex { $0["type"] as? String == "fallback" }).map { $0 + 1 } ?? 0
        return blocks[start...]
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
    }

    /// Applies one event. Returns true when the visible text changed.
    mutating func apply(_ event: [String: Any]) throws -> Bool {
        switch event["type"] as? String {
        case "content_block_start":
            guard let index = event["index"] as? Int, let block = event["content_block"] as? [String: Any] else { return false }
            while blocks.count <= index { blocks.append([:]) }
            blocks[index] = block
            return block["type"] as? String == "fallback"

        case "content_block_delta":
            guard let index = event["index"] as? Int, index < blocks.count,
                  let delta = event["delta"] as? [String: Any] else { return false }
            switch delta["type"] as? String {
            case "text_delta":
                blocks[index]["text"] = (blocks[index]["text"] as? String ?? "") + (delta["text"] as? String ?? "")
                return true
            case "thinking_delta":
                blocks[index]["thinking"] = (blocks[index]["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
            case "signature_delta":
                blocks[index]["signature"] = (blocks[index]["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
            default:
                break
            }
            return false

        case "message_delta":
            if let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                stopReason = reason
            }
            return false

        case "error":
            let error = event["error"] as? [String: Any]
            throw LLMError.server(error?["message"] as? String ?? "Claude returned an error.")

        default:
            return false
        }
    }
}
