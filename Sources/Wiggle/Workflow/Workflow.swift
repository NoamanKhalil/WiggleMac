import CoreGraphics
import Foundation

/// A recorded sequence of clicks, drags, scrolls and key presses, replayed at the same
/// screen coordinates (global display space, origin at the top-left of the main display).
struct Workflow: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var created = Date()
    var steps: [WorkflowStep]
    /// Set on the edited copy that chat changes are saved to, leaving the original as recorded.
    var editedFrom: Workflow.ID? = nil

    /// How long one run takes at recorded speed.
    var duration: TimeInterval { Self.duration(of: steps) }

    var summary: String { Self.summary(of: steps) }

    static func duration(of steps: [WorkflowStep]) -> TimeInterval {
        steps.reduce(0) { $0 + $1.delay + $1.action.duration }
    }

    /// "14 steps · 22 s"
    static func summary(of steps: [WorkflowStep]) -> String {
        let count = steps.count == 1 ? "1 step" : "\(steps.count) steps"
        let seconds = Int(duration(of: steps).rounded())
        let time = seconds < 1 ? "under 1 s" : seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
        return "\(count) · \(time)"
    }
}

struct WorkflowStep: Codable, Hashable, Sendable {
    /// Wait before this step, measured from the end of the previous one.
    var delay: TimeInterval
    var action: WorkflowAction
}

enum MouseButton: String, Codable, Hashable, Sendable {
    case left, right, other
}

enum WorkflowAction: Codable, Hashable, Sendable {
    /// `count` is the click count: 2 for the second click of a double-click.
    case click(at: CGPoint, button: MouseButton, count: Int, modifiers: UInt64)
    case drag(from: CGPoint, to: CGPoint, button: MouseButton, duration: TimeInterval, modifiers: UInt64)
    /// Deltas in points, as `CGEvent`'s scroll point-delta fields report them.
    case scroll(at: CGPoint, dx: Double, dy: Double, duration: TimeInterval)
    case key(code: UInt16, modifiers: UInt64, characters: String)
    /// Types `text` whatever the keyboard layout: for characters no key on it types (emoji, say).
    case text(String)

    /// Shift, Control, Option and Command: the modifiers worth recording and replaying.
    static let modifierMask: UInt64 = CGEventFlags([.maskShift, .maskControl, .maskAlternate, .maskCommand]).rawValue

    var duration: TimeInterval {
        switch self {
        case .drag(_, _, _, let duration, _), .scroll(_, _, _, let duration): duration
        case .click, .key, .text: 0
        }
    }

    /// Where the action lands on screen. A drag's path is sampled every few points.
    var points: [CGPoint] {
        switch self {
        case .click(let point, _, _, _), .scroll(let point, _, _, _):
            return [point]
        case .drag(let from, let to, _, _, _):
            let samples = max(1, Int(hypot(to.x - from.x, to.y - from.y) / 8))
            return (0...samples).map { index in
                let t = CGFloat(index) / CGFloat(samples)
                return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            }
        case .key, .text:
            return []
        }
    }
}

/// Turns raw input into workflow steps. Pure, so it can be tested without real events.
struct WorkflowBuilder {
    enum Input {
        case mouseDown(CGPoint, MouseButton, clickCount: Int, modifiers: UInt64)
        case mouseUp(CGPoint, MouseButton)
        case scroll(CGPoint, dx: Double, dy: Double)
        case key(code: UInt16, modifiers: UInt64, characters: String)
    }

    /// Movement between press and release that turns a click into a drag.
    static let dragThreshold: CGFloat = 4
    /// Scroll events closer together than this become one scroll step.
    static let scrollGap: TimeInterval = 0.35
    /// The wait before the first step is time spent reaching for the mouse; keep it short.
    static let maxFirstDelay: TimeInterval = 1

    private(set) var steps: [WorkflowStep] = []
    private var lastEnd: TimeInterval
    private var pressed: (point: CGPoint, button: MouseButton, count: Int, modifiers: UInt64, time: TimeInterval)?
    private var scrolling: (point: CGPoint, dx: Double, dy: Double, start: TimeInterval, last: TimeInterval)?
    private var pausedAt: TimeInterval?

    init(start: TimeInterval) {
        lastEnd = start
    }

    /// Ignores input until `resume`. A button held down is dropped, as at the end.
    mutating func pause(at time: TimeInterval) {
        guard pausedAt == nil else { return }
        flushScroll()
        pressed = nil
        pausedAt = time
    }

    /// Time spent paused doesn't count toward the wait before the next step.
    mutating func resume(at time: TimeInterval) {
        guard let pausedAt else { return }
        lastEnd += time - pausedAt
        self.pausedAt = nil
    }

    mutating func add(_ input: Input, at time: TimeInterval) {
        guard pausedAt == nil else { return }
        switch input {
        case .mouseDown(let point, let button, let count, let modifiers):
            flushScroll()
            guard pressed == nil else { return }
            pressed = (point, button, count, modifiers, time)

        case .mouseUp(let point, let button):
            guard let down = pressed, down.button == button else { return }
            pressed = nil
            if hypot(point.x - down.point.x, point.y - down.point.y) < Self.dragThreshold {
                append(.click(at: down.point, button: button, count: max(1, down.count), modifiers: down.modifiers), startingAt: down.time)
            } else {
                append(.drag(from: down.point, to: point, button: button, duration: time - down.time, modifiers: down.modifiers),
                       startingAt: down.time)
            }
            lastEnd = time

        case .scroll(let point, let dx, let dy):
            if var current = scrolling, time - current.last <= Self.scrollGap {
                current.dx += dx
                current.dy += dy
                current.last = time
                scrolling = current
            } else {
                flushScroll()
                scrolling = (point, dx, dy, time, time)
            }

        case .key(let code, let modifiers, let characters):
            flushScroll()
            append(.key(code: code, modifiers: modifiers, characters: characters), startingAt: time)
            lastEnd = time
        }
    }

    /// Ends the recording. A button still held down is dropped.
    mutating func finish() -> [WorkflowStep] {
        flushScroll()
        pressed = nil
        return steps
    }

    private mutating func flushScroll() {
        guard let scroll = scrolling else { return }
        scrolling = nil
        guard scroll.dx != 0 || scroll.dy != 0 else { return }
        append(.scroll(at: scroll.point, dx: scroll.dx, dy: scroll.dy, duration: scroll.last - scroll.start), startingAt: scroll.start)
        lastEnd = scroll.last
    }

    private mutating func append(_ action: WorkflowAction, startingAt time: TimeInterval) {
        var delay = max(0, time - lastEnd)
        if steps.isEmpty { delay = min(delay, Self.maxFirstDelay) }
        steps.append(WorkflowStep(delay: delay, action: action))
    }
}

/// One row in a list of steps. Typing shares a row, Backspace corrections included ("Type “hello”"),
/// and so does the same key pressed again and again ("Press Esc ×3").
struct WorkflowStepGroup: Identifiable, Equatable {
    let range: Range<Int>
    let title: String
    let symbol: String
    /// For typing: the text it leaves, after any corrections.
    var text: String?

    var id: Int { range.lowerBound }

    static func groups(for steps: [WorkflowStep]) -> [WorkflowStepGroup] {
        var groups: [WorkflowStepGroup] = []
        var index = 0
        while index < steps.count {
            if typedText(steps[index].action) != nil {
                var end = index
                var text = ""
                while end < steps.count {
                    if let typed = typedText(steps[end].action) {
                        text += typed
                    } else if isBackspace(steps[end].action), !text.isEmpty {
                        text.removeLast()
                    } else {
                        break
                    }
                    end += 1
                }
                let line = text.replacingOccurrences(of: "\n", with: " ")
                let shown = line.count > 36 ? String(line.prefix(35)) + "…" : line
                groups.append(WorkflowStepGroup(range: index..<end, title: "Type “\(shown)”", symbol: "character.cursor.ibeam", text: text))
                index = end
            } else {
                var end = index + 1
                if case .key = steps[index].action {
                    while end < steps.count, steps[end].action == steps[index].action { end += 1 }
                }
                let (title, symbol) = describe(steps[index].action)
                let count = end - index
                groups.append(WorkflowStepGroup(range: index..<end, title: count > 1 ? "\(title) ×\(count)" : title, symbol: symbol))
                index = end
            }
        }
        return groups
    }

    /// The text a step types, or nil for shortcuts and special keys.
    private static func typedText(_ action: WorkflowAction) -> String? {
        switch action {
        case .text(let text):
            return text
        case .key(let code, let modifiers, let characters):
            // Shift-Return breaks a line in a message, where Return alone would send it.
            if code == 36 || code == 76, modifiers == CGEventFlags.maskShift.rawValue { return "\n" }
            let shortcut = CGEventFlags([.maskCommand, .maskControl]).rawValue
            guard modifiers & shortcut == 0, specialKeys[code] == nil || code == 49 else { return nil }
            if code == 49 { return " " }
            guard !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return characters
        default:
            return nil
        }
    }

    private static func isBackspace(_ action: WorkflowAction) -> Bool {
        if case .key(51, 0, _) = action { true } else { false }
    }

    private static func describe(_ action: WorkflowAction) -> (String, String) {
        switch action {
        case .click(let point, let button, let count, let modifiers):
            let kind = button == .right ? "Right-click" : count >= 2 ? "Double-click" : "Click"
            return ("\(symbols(modifiers))\(kind) at \(position(point))", count >= 2 ? "cursorarrow.click.2" : "cursorarrow.click")
        case .drag(let from, let to, _, _, let modifiers):
            return ("\(symbols(modifiers))Drag from \(position(from)) to \(position(to))", "hand.draw")
        case .scroll(let point, _, _, _):
            return ("Scroll at \(position(point))", "scroll")
        case .key(let code, let modifiers, let characters):
            let name = specialKeys[code] ?? (characters.isEmpty ? "Key \(code)" : characters.uppercased())
            return ("Press \(symbols(modifiers))\(name)", "keyboard")
        case .text(let text):
            return ("Type “\(text)”", "character.cursor.ibeam")
        }
    }

    private static let specialKeys: [UInt16: String] = [
        36: "↩", 76: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    ]

    private static func symbols(_ modifiers: UInt64) -> String {
        let flags = CGEventFlags(rawValue: modifiers)
        var text = ""
        if flags.contains(.maskControl) { text += "⌃" }
        if flags.contains(.maskAlternate) { text += "⌥" }
        if flags.contains(.maskShift) { text += "⇧" }
        if flags.contains(.maskCommand) { text += "⌘" }
        return text
    }

    private static func position(_ point: CGPoint) -> String {
        "\(Int(point.x.rounded())), \(Int(point.y.rounded()))"
    }
}
