import Foundation
import Testing
@testable import Wiggle

struct AnthropicStreamTests {
    private func events(_ lines: [String]) -> [[String: Any]] {
        lines.map { try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
    }

    @Test func rebuildsThinkingAndTextBlocks() throws {
        var accumulator = AnthropicStreamAccumulator()
        for event in events([
            #"{"type":"message_start","message":{"id":"msg_1"}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig123"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":", world"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
            #"{"type":"message_stop"}"#,
        ]) {
            _ = try accumulator.apply(event)
        }
        #expect(accumulator.visibleText == "Hello, world")
        #expect(accumulator.stopReason == "end_turn")
        #expect(accumulator.blocks.count == 2)
        #expect(accumulator.blocks[0]["type"] as? String == "thinking")
        #expect(accumulator.blocks[0]["thinking"] as? String == "")
        #expect(accumulator.blocks[0]["signature"] as? String == "sig123")
    }

    @Test func showsOnlyTextAfterAFallback() throws {
        var accumulator = AnthropicStreamAccumulator()
        for event in events([
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Partial"}}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"fallback","from":{"model":"a"},"to":{"model":"b"}}}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Answer"}}"#,
        ]) {
            _ = try accumulator.apply(event)
        }
        #expect(accumulator.visibleText == "Answer")
        #expect(accumulator.blocks.count == 3)
    }

    @Test func surfacesStreamErrors() {
        var accumulator = AnthropicStreamAccumulator()
        let event = events([#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#])[0]
        #expect(throws: LLMError.self) { try accumulator.apply(event) }
    }
}
