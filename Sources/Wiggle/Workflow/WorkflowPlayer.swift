import AppKit

/// Replays a workflow by posting the recorded input at the recorded screen coordinates.
/// Needs Accessibility permission. Esc pauses and resumes it; a wiggle (handled by the app) stops it.
@MainActor
@Observable
final class WorkflowPlayer {
    private(set) var isPlaying = false
    private(set) var isPaused = false
    private(set) var workflow: Workflow?
    /// Zero-based: the step being played or waited on, the run it's in, and how many runs there are.
    private(set) var step = 0
    private(set) var run = 0
    private(set) var runs = 1

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored var onPauseChanged: (() -> Void)?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var escapeTap: EscapeKeyTap?
    @ObservationIgnored private var resumeWaiter: CheckedContinuation<Void, Never>?
    @ObservationIgnored private let source = CGEventSource(stateID: .hidSystemState)

    /// Runs `workflow` `times` times in a row, starting after `delay`.
    func play(_ workflow: Workflow, times: Int, after delay: Duration = .zero) {
        guard !isPlaying, !workflow.steps.isEmpty else { return }
        self.workflow = workflow
        runs = max(1, times)
        run = 0
        step = 0
        isPlaying = true
        escapeTap = EscapeKeyTap { [weak self] in self?.togglePause() }
        task = Task { [weak self] in
            try? await self?.replay(workflow, after: delay)
            self?.finished()
        }
    }

    /// Takes effect between steps, so a pause never leaves a mouse button held down.
    func togglePause() {
        guard isPlaying else { return }
        isPaused.toggle()
        if !isPaused {
            resumeWaiter?.resume()
            resumeWaiter = nil
        }
        onPauseChanged?()
    }

    func stop() {
        task?.cancel()
        resumeWaiter?.resume()
        resumeWaiter = nil
    }

    private func replay(_ workflow: Workflow, after delay: Duration) async throws {
        try await wait(delay)
        for run in 0..<runs {
            self.run = run
            self.step = 0
            if run > 0 { try await wait(.milliseconds(500)) }
            for (index, step) in workflow.steps.enumerated() {
                self.step = index
                try await wait(.seconds(step.delay))
                try await perform(step.action)
            }
        }
    }

    /// Sleeps for `duration` of unpaused time: pausing partway through a wait keeps the rest of it.
    private func wait(_ duration: Duration) async throws {
        try await untilResumed()
        let clock = ContinuousClock()
        var remaining = duration
        while remaining > .zero {
            let start = clock.now
            try await Task.sleep(for: min(remaining, .milliseconds(50)))
            remaining -= start.duration(to: clock.now)
            try await untilResumed()
        }
    }

    private func untilResumed() async throws {
        while isPaused, !Task.isCancelled {
            await withCheckedContinuation { resumeWaiter = $0 }
        }
        try Task.checkCancellation()
    }

    private func finished() {
        escapeTap?.invalidate()
        escapeTap = nil
        task = nil
        workflow = nil
        isPaused = false
        isPlaying = false
        onFinish?()
    }

    private func perform(_ action: WorkflowAction) async throws {
        try Task.checkCancellation()
        switch action {
        case .click(let point, let button, let count, let modifiers):
            post(mouse: .moved(button), at: point, button: button)
            try await Task.sleep(for: .milliseconds(30))
            post(mouse: .down(button), at: point, button: button, clickState: count, modifiers: modifiers)
            post(mouse: .up(button), at: point, button: button, clickState: count, modifiers: modifiers)

        case .drag(let from, let to, let button, let duration, let modifiers):
            post(mouse: .moved(button), at: from, button: button)
            try await Task.sleep(for: .milliseconds(30))
            post(mouse: .down(button), at: from, button: button, modifiers: modifiers)
            let moves = max(2, min(60, Int(duration / 0.016)))
            var point = from
            do {
                for index in 1...moves {
                    try await Task.sleep(for: .seconds(max(duration, 0.1) / Double(moves)))
                    let t = CGFloat(index) / CGFloat(moves)
                    point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
                    post(mouse: .dragged(button), at: point, button: button, modifiers: modifiers)
                }
            } catch {
                // Stopped mid-drag: let go of the button rather than leave it held down.
                post(mouse: .up(button), at: point, button: button, modifiers: modifiers)
                throw error
            }
            post(mouse: .up(button), at: to, button: button, modifiers: modifiers)

        case .scroll(let point, let dx, let dy, let duration):
            post(mouse: .moved(.left), at: point, button: .left)
            let chunks = max(1, min(30, Int(duration / 0.016)))
            for index in 0..<chunks {
                if index > 0 { try await Task.sleep(for: .seconds(duration / Double(chunks))) }
                guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                          wheel1: Int32((dy / Double(chunks)).rounded()),
                                          wheel2: Int32((dx / Double(chunks)).rounded()), wheel3: 0)
                else { continue }
                event.location = point
                send(event)
            }

        case .key(let code, let modifiers, _):
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else { continue }
                event.flags = CGEventFlags(rawValue: modifiers)
                send(event)
            }

        case .text(let text):
            let units = Array(text.utf16)
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown) else { continue }
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                send(event)
            }
        }
    }

    private enum Phase {
        case moved(MouseButton), down(MouseButton), up(MouseButton), dragged(MouseButton)

        var type: CGEventType {
            switch self {
            case .moved: .mouseMoved
            case .down(.left): .leftMouseDown
            case .down(.right): .rightMouseDown
            case .down(.other): .otherMouseDown
            case .up(.left): .leftMouseUp
            case .up(.right): .rightMouseUp
            case .up(.other): .otherMouseUp
            case .dragged(.left): .leftMouseDragged
            case .dragged(.right): .rightMouseDragged
            case .dragged(.other): .otherMouseDragged
            }
        }
    }

    private func post(mouse phase: Phase, at point: CGPoint, button: MouseButton, clickState: Int = 1, modifiers: UInt64 = 0) {
        let cgButton: CGMouseButton = switch button {
        case .left: .left
        case .right: .right
        case .other: .center
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: phase.type, mouseCursorPosition: point, mouseButton: cgButton)
        else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        event.flags = CGEventFlags(rawValue: modifiers)
        send(event)
    }

    private func send(_ event: CGEvent) {
        SyntheticInput.tag(event)
        event.post(tap: .cghidEventTap)
    }
}

/// Catches Esc while a workflow runs or records, before the app in front sees it, so pausing doesn't
/// also close the menu or dialog the workflow just opened. Needs Accessibility permission, as both do.
@MainActor
final class EscapeKeyTap {
    private static let escape: Int64 = 53
    private let onPress: () -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<EscapeKeyTap>.fromOpaque(info).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { owner.handle(type, event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
    }

    func invalidate() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    /// True swallows the event. Esc keys a workflow presses itself pass through.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown, .keyUp:
            guard event.getIntegerValueField(.keyboardEventKeycode) == Self.escape, !SyntheticInput.isSynthetic(event)
            else { return false }
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { onPress() }
            return true
        default:
            return false
        }
    }
}
