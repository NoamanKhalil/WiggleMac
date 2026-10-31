import Carbon
import CoreGraphics
import Foundation

/// Which key, with which modifiers, types each character on a keyboard layout.
struct KeyLayout {
    var keys: [Character: (code: UInt16, modifiers: UInt64)]

    /// The layout in use now. Characters it can't type, and every character if it can't be read,
    /// become `.text` steps instead.
    @MainActor static func current() -> KeyLayout {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return KeyLayout(keys: [:]) }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        let shift = CGEventFlags.maskShift.rawValue, option = CGEventFlags.maskAlternate.rawValue
        // Fewest modifiers first, so each character gets its plainest key.
        let states: [(flags: UInt64, carbon: Int)] = [(0, 0), (shift, shiftKey), (option, optionKey), (shift | option, shiftKey | optionKey)]
        var keys: [Character: (code: UInt16, modifiers: UInt64)] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for state in states {
                for code in UInt16(0)..<128 {
                    var deadKeys: UInt32 = 0
                    var length = 0
                    var units = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), UInt32(state.carbon >> 8) & 0xFF,
                                                UInt32(LMGetKbdType()), 0, &deadKeys, units.count, &length, &units)
                    // Dead keys (Option-E for an accent) type nothing until the next key: skip them.
                    guard status == noErr, length > 0, deadKeys == 0 else { continue }
                    let string = String(utf16CodeUnits: units, count: length)
                    guard string.count == 1, let character = string.first, keys[character] == nil,
                          string.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
                    else { continue }
                    keys[character] = (code, state.flags)
                }
            }
        }
        return KeyLayout(keys: keys)
    }

    /// Steps that type `text`: the first after `delay`, the rest spaced like `rhythm`, the gaps
    /// between keys when it was recorded. Line breaks are Shift-Return.
    func typing(_ text: String, after delay: TimeInterval, rhythm: [TimeInterval]) -> [WorkflowStep] {
        let gaps = rhythm.isEmpty ? [0.15] : rhythm
        var steps: [WorkflowStep] = []
        for character in text {
            let action: WorkflowAction
            if character.isNewline {
                action = .key(code: 36, modifiers: CGEventFlags.maskShift.rawValue, characters: "\n")
            } else if character.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
                continue
            } else if let key = keys[character] {
                action = .key(code: key.code, modifiers: key.modifiers, characters: String(character))
            } else {
                action = .text(String(character))
            }
            let wait = steps.isEmpty ? delay : gaps[(steps.count - 1) % gaps.count]
            steps.append(WorkflowStep(delay: wait, action: action))
        }
        return steps
    }
}

/// Changes a model proposes to a workflow, by step number in `WorkflowStepGroup.groups`, counting from 1.
struct WorkflowEdits: Equatable {
    /// New text for typing steps.
    var texts: [Int: String] = [:]
    var removed: Set<Int> = []

    var isEmpty: Bool { texts.isEmpty && removed.isEmpty }

    private static var typeTag: Regex<(Substring, Substring, Substring)> {
        /<type\s+step\s*=\s*"?(\d+)"?\s*>(.*?)<\/type>/.dotMatchesNewlines()
    }
    private static var removeTag: Regex<(Substring, Substring)> { /<remove\s+steps?\s*=\s*"([\d\s,–-]+)"\s*\/?>/ }

    /// Reads `<type step="7">…</type>` and `<remove steps="9-11"/>` out of a reply. The prose is the rest,
    /// and stops before a tag that's still streaming in.
    static func parse(_ reply: String) -> (prose: String, edits: WorkflowEdits) {
        var edits = WorkflowEdits()
        for match in reply.matches(of: typeTag) {
            guard let step = Int(match.1) else { continue }
            edits.texts[step] = String(match.2).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for match in reply.matches(of: removeTag) {
            for part in match.1.split(separator: ",") {
                let bounds = part.split(whereSeparator: { $0 == "-" || $0 == "–" })
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if bounds.count == 1 { edits.removed.insert(bounds[0]) }
                if bounds.count == 2, bounds[0] <= bounds[1] { edits.removed.formUnion(bounds[0]...bounds[1]) }
            }
        }
        var prose = reply.replacing(typeTag, with: "").replacing(removeTag, with: "")
        if let open = prose.firstRange(of: /<(type|remove)\b/) {
            prose = String(prose[..<open.lowerBound])
        }
        prose = prose.replacing(/\n{3,}/, with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (prose, edits)
    }

    /// Why each change that can't be made can't, by step number: models do get the numbers wrong.
    func problems(in steps: [WorkflowStep]) -> [Int: String] {
        let groups = WorkflowStepGroup.groups(for: steps)
        var problems: [Int: String] = [:]
        for step in removed.union(texts.keys) where !groups.indices.contains(step - 1) {
            problems[step] = "There's no step \(step)."
        }
        for step in texts.keys where groups.indices.contains(step - 1) && !removed.contains(step) {
            if groups[step - 1].text == nil {
                problems[step] = "Step \(step) is “\(groups[step - 1].title)”, which doesn't type anything."
            }
        }
        return problems
    }

    /// `steps` with the changes made, or nil if any doesn't fit (see `problems`) or nothing would be left.
    /// New text is typed at the rhythm the step was recorded at.
    func applied(to steps: [WorkflowStep], keys: KeyLayout) -> [WorkflowStep]? {
        guard problems(in: steps).isEmpty else { return nil }
        let groups = WorkflowStepGroup.groups(for: steps)

        var result: [WorkflowStep] = []
        for (index, group) in groups.enumerated() where !removed.contains(index + 1) {
            if let text = texts[index + 1] {
                let original = steps[group.range]
                result += keys.typing(text, after: original.first?.delay ?? 0, rhythm: original.dropFirst().map(\.delay))
            } else {
                result += steps[group.range]
            }
        }
        return result.isEmpty ? nil : result
    }
}
