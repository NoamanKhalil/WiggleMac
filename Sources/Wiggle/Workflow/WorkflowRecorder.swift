import AppKit
import ApplicationServices

/// Input Wiggle posts itself carries this tag, so the wiggle detector and the recorder skip it.
enum SyntheticInput {
    static let marker: Int64 = 0x5749_474C  // "WIGL"

    static func tag(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }

    static func isSynthetic(_ event: CGEvent?) -> Bool {
        event?.getIntegerValueField(.eventSourceUserData) == marker
    }
}

/// Recording keystrokes and replaying input both need Accessibility permission.
enum Accessibility {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Adds Wiggle to the Accessibility list in System Settings and shows the system prompt.
    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

/// Records clicks, drags, scrolling and typing in other apps. Wiggle's own windows aren't recorded,
/// and macOS withholds keystrokes typed into password fields. Esc pauses and resumes, and isn't recorded.
@MainActor
@Observable
final class WorkflowRecorder {
    private(set) var isRecording = false
    private(set) var isPaused = false
    private var builder = WorkflowBuilder(start: 0)

    @ObservationIgnored var onPauseChanged: (() -> Void)?

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var escapeTap: EscapeKeyTap?

    var stepCount: Int { builder.steps.count }

    func start() {
        guard !isRecording else { return }
        builder = WorkflowBuilder(start: ProcessInfo.processInfo.systemUptime)
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .scrollWheel, .keyDown,
        ]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        escapeTap = EscapeKeyTap { [weak self] in self?.togglePause() }
        isRecording = true
    }

    /// Paused, nothing is recorded, and the time doesn't become a wait in the workflow.
    func togglePause() {
        guard isRecording else { return }
        isPaused.toggle()
        let now = ProcessInfo.processInfo.systemUptime
        if isPaused { builder.pause(at: now) } else { builder.resume(at: now) }
        onPauseChanged?()
    }

    func stop() -> [WorkflowStep] {
        guard isRecording else { return [] }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        escapeTap?.invalidate()
        escapeTap = nil
        isRecording = false
        isPaused = false
        return builder.finish()
    }

    private func handle(_ event: NSEvent) {
        guard let cgEvent = event.cgEvent, !SyntheticInput.isSynthetic(cgEvent) else { return }
        let point = cgEvent.location
        let modifiers = cgEvent.flags.rawValue & WorkflowAction.modifierMask
        let input: WorkflowBuilder.Input
        switch event.type {
        case .leftMouseDown: input = .mouseDown(point, .left, clickCount: event.clickCount, modifiers: modifiers)
        case .rightMouseDown: input = .mouseDown(point, .right, clickCount: event.clickCount, modifiers: modifiers)
        case .otherMouseDown: input = .mouseDown(point, .other, clickCount: event.clickCount, modifiers: modifiers)
        case .leftMouseUp: input = .mouseUp(point, .left)
        case .rightMouseUp: input = .mouseUp(point, .right)
        case .otherMouseUp: input = .mouseUp(point, .other)
        case .scrollWheel:
            input = .scroll(point,
                            dx: cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
                            dy: cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        case .keyDown:
            // Typed text as typed ("H", "é"); shortcuts by their key ("v" for ⌘V). Only used for display:
            // replay presses the same key with the same modifiers.
            let isShortcut = modifiers & CGEventFlags([.maskCommand, .maskControl]).rawValue != 0
            let characters = (isShortcut ? event.charactersIgnoringModifiers : event.characters) ?? ""
            input = .key(code: event.keyCode, modifiers: modifiers, characters: characters)
        default:
            return
        }
        builder.add(input, at: event.timestamp)
    }
}
