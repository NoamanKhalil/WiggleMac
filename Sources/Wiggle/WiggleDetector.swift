import AppKit

/// Watches global mouse movement and fires when the pointer is shaken
/// back and forth quickly (several direction reversals in a short window).
@MainActor
final class WiggleDetector {
    var onWiggle: ((CGPoint) -> Void)?

    var sensitivity: Sensitivity = .medium
    var isEnabled = true

    private let window: TimeInterval = 0.9
    private let cooldown: TimeInterval = 1.2

    private var monitors: [Any] = []
    private var x = AxisTracker()
    private var y = AxisTracker()
    private var lastFire: TimeInterval = 0

    func start() {
        guard monitors.isEmpty else { return }
        // Plain moves only: wiggling while dragging (windows, selections) shouldn't trigger.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleMove(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleMove(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handleMove(_ event: NSEvent) {
        // Pointer moves from replaying a workflow aren't the user wiggling.
        guard isEnabled, !SyntheticInput.isSynthetic(event.cgEvent) else { return }
        let point = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let minStroke = sensitivity.minStroke

        x.add(point.x, at: now, minStroke: minStroke, window: window)
        y.add(point.y, at: now, minStroke: minStroke, window: window)

        let required = sensitivity.requiredReversals
        guard x.reversals.count >= required || y.reversals.count >= required else { return }
        guard now - lastFire > cooldown else { return }

        lastFire = now
        x = AxisTracker()
        y = AxisTracker()
        onWiggle?(point)
    }
}

/// Counts direction reversals along one axis.
struct AxisTracker {
    private var last: Double?
    private var direction: Double = 0
    private var strokeStart: Double = 0
    private(set) var reversals: [TimeInterval] = []

    mutating func add(_ value: Double, at time: TimeInterval, minStroke: Double, window: TimeInterval) {
        reversals.removeAll { time - $0 > window }

        guard let last else {
            self.last = value
            strokeStart = value
            return
        }
        let delta = value - last
        guard abs(delta) >= 1 else { return }

        let newDirection: Double = delta > 0 ? 1 : -1
        if direction == 0 {
            direction = newDirection
            strokeStart = last
        } else if newDirection != direction {
            // Short jitters don't count, but still start a fresh stroke.
            if abs(last - strokeStart) >= minStroke {
                reversals.append(time)
            }
            direction = newDirection
            strokeStart = last
        }
        self.last = value
    }
}
