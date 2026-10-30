import Foundation
import Testing
@testable import Wiggle

struct AxisTrackerTests {
    /// Feeds a sine-shaped back-and-forth motion sampled at 120 Hz.
    private func shake(amplitude: Double, period: Double, duration: Double) -> AxisTracker {
        var tracker = AxisTracker()
        var t = 0.0
        while t < duration {
            let value = 500 + amplitude * sin(2 * .pi * t / period)
            tracker.add(value, at: t, minStroke: Sensitivity.medium.minStroke, window: 0.9)
            t += 1.0 / 120
        }
        return tracker
    }

    @Test func fastWideShakeCountsReversals() {
        // ~6 half-strokes of 160 pt in 0.75 s.
        let tracker = shake(amplitude: 80, period: 0.25, duration: 0.75)
        #expect(tracker.reversals.count >= Sensitivity.medium.requiredReversals)
    }

    @Test func smallJitterIsIgnored() {
        let tracker = shake(amplitude: 8, period: 0.1, duration: 0.9)
        #expect(tracker.reversals.isEmpty)
    }

    @Test func slowBackAndForthDoesNotTrigger() {
        // One reversal every ~0.75 s: ordinary pointing, not a wiggle.
        let tracker = shake(amplitude: 200, period: 1.5, duration: 3)
        #expect(tracker.reversals.count < Sensitivity.medium.requiredReversals)
    }

    @Test func straightLineHasNoReversals() {
        var tracker = AxisTracker()
        for i in 0..<120 {
            tracker.add(Double(i) * 10, at: Double(i) / 120, minStroke: 40, window: 0.9)
        }
        #expect(tracker.reversals.isEmpty)
    }
}
