import CoreGraphics
import Foundation
import Testing
@testable import Wiggle

struct WorkflowBuilderTests {
    private let command = CGEventFlags.maskCommand.rawValue

    @Test func pressAndReleaseInPlaceIsAClick() {
        var builder = WorkflowBuilder(start: 10)
        builder.add(.mouseDown(CGPoint(x: 100, y: 200), .left, clickCount: 1, modifiers: 0), at: 10.5)
        builder.add(.mouseUp(CGPoint(x: 101, y: 201), .left), at: 10.6)
        let steps = builder.finish()
        #expect(steps == [WorkflowStep(delay: 0.5, action: .click(at: CGPoint(x: 100, y: 200), button: .left, count: 1, modifiers: 0))])
    }

    @Test func movingWhilePressedIsADrag() {
        var builder = WorkflowBuilder(start: 0)
        builder.add(.mouseDown(CGPoint(x: 10, y: 10), .left, clickCount: 1, modifiers: 0), at: 0.2)
        builder.add(.mouseUp(CGPoint(x: 300, y: 40), .left), at: 0.9)
        let steps = builder.finish()
        #expect(steps.count == 1)
        guard case .drag(let from, let to, .left, let duration, _) = steps[0].action else {
            Issue.record("expected a drag, got \(steps[0].action)")
            return
        }
        #expect(from == CGPoint(x: 10, y: 10))
        #expect(to == CGPoint(x: 300, y: 40))
        #expect(abs(duration - 0.7) < 0.0001)
    }

    @Test func delaysAreMeasuredFromTheEndOfTheLastStep() {
        var builder = WorkflowBuilder(start: 0)
        builder.add(.mouseDown(.zero, .left, clickCount: 1, modifiers: 0), at: 0.1)
        builder.add(.mouseUp(.zero, .left), at: 0.3)
        builder.add(.key(code: 0, modifiers: 0, characters: "a"), at: 2.3)
        let steps = builder.finish()
        #expect(steps.count == 2)
        #expect(abs(steps[0].delay - 0.1) < 0.0001)
        #expect(abs(steps[1].delay - 2.0) < 0.0001)
    }

    @Test func capsTheWaitBeforeTheFirstStep() {
        var builder = WorkflowBuilder(start: 0)
        builder.add(.key(code: 0, modifiers: 0, characters: "a"), at: 6)
        #expect(builder.finish().first?.delay == WorkflowBuilder.maxFirstDelay)
    }

    @Test func keepsDoubleClicks() {
        var builder = WorkflowBuilder(start: 0)
        for (count, time) in [(1, 0.1), (2, 0.3)] {
            builder.add(.mouseDown(CGPoint(x: 5, y: 5), .left, clickCount: count, modifiers: 0), at: time)
            builder.add(.mouseUp(CGPoint(x: 5, y: 5), .left), at: time + 0.05)
        }
        let counts = builder.finish().compactMap { step -> Int? in
            if case .click(_, _, let count, _) = step.action { return count }
            return nil
        }
        #expect(counts == [1, 2])
    }

    @Test func mergesNearbyScrollEvents() {
        var builder = WorkflowBuilder(start: 0)
        for (index, time) in [0.0, 0.1, 0.2].enumerated() {
            builder.add(.scroll(CGPoint(x: 50, y: 50), dx: 0, dy: Double(-10 * (index + 1))), at: time)
        }
        builder.add(.scroll(CGPoint(x: 50, y: 50), dx: 0, dy: -5), at: 2.0)
        let steps = builder.finish()
        #expect(steps.count == 2)
        guard case .scroll(_, _, let dy, let duration) = steps[0].action else {
            Issue.record("expected a scroll")
            return
        }
        #expect(dy == -60)
        #expect(abs(duration - 0.2) < 0.0001)
    }

    @Test func dropsAButtonStillHeldWhenRecordingStops() {
        var builder = WorkflowBuilder(start: 0)
        builder.add(.key(code: 8, modifiers: command, characters: "c"), at: 0.1)
        builder.add(.mouseDown(.zero, .left, clickCount: 1, modifiers: 0), at: 0.2)
        #expect(builder.finish().count == 1)
    }
}

struct WorkflowStepGroupTests {
    private func key(_ characters: String, code: UInt16 = 0, modifiers: CGEventFlags = []) -> WorkflowStep {
        WorkflowStep(delay: 0.1, action: .key(code: code, modifiers: modifiers.rawValue, characters: characters))
    }

    @Test func mergesTypingAndKeepsShortcutsApart() {
        let steps = [
            WorkflowStep(delay: 0, action: .click(at: CGPoint(x: 812, y: 440), button: .left, count: 1, modifiers: 0)),
            key("H", modifiers: .maskShift), key("i"), key(" ", code: 49), key("!", modifiers: .maskShift),
            key("v", code: 9, modifiers: .maskCommand),
            key("\r", code: 36),
        ]
        let groups = WorkflowStepGroup.groups(for: steps)
        #expect(groups.map(\.title) == ["Click at 812, 440", "Type “Hi !”", "Press ⌘V", "Press ↩"])
        #expect(groups[1].range == 1..<5)
    }

    @Test func summarizesStepsAndDuration() {
        let steps = [key("a"), key("b")]
        #expect(Workflow.summary(of: steps) == "2 steps · under 1 s")
        #expect(Workflow.summary(of: [WorkflowStep(delay: 75, action: .key(code: 0, modifiers: 0, characters: "a"))]) == "1 step · 1 min 15 s")
    }
}

struct WorkflowStoreTests {
    @Test @MainActor func savesAndReloads() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "wiggle-tests-\(UUID().uuidString)/workflows.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = WorkflowStore(url: url)
        #expect(store.nextDefaultName == "Workflow 1")
        let workflow = Workflow(name: "Copy totals", steps: [
            WorkflowStep(delay: 0.2, action: .drag(from: .zero, to: CGPoint(x: 9, y: 9), button: .left, duration: 0.4, modifiers: 0)),
            WorkflowStep(delay: 0.1, action: .scroll(at: CGPoint(x: 1, y: 2), dx: 0, dy: -40, duration: 0.2)),
        ])
        store.add(workflow)

        let reloaded = WorkflowStore(url: url)
        #expect(reloaded.workflows == [workflow])
        #expect(reloaded.nextDefaultName == "Workflow 2")
        reloaded.delete(workflow.id)
        #expect(WorkflowStore(url: url).workflows.isEmpty)
    }

    @Test @MainActor func setsAsideAnUnreadableFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "wiggle-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.appending(path: "workflows.json"))

        let store = WorkflowStore(url: folder.appending(path: "workflows.json"))
        #expect(store.workflows.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains { $0.hasPrefix("workflows-unreadable-") })
    }
}

struct WorkflowControlsPlacementTests {
    private let size = CGSize(width: 320, height: 62)
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func sitsAtTheBottomCenterWhenNothingIsThere() {
        let frame = WorkflowControlsController.frame(size: size, in: screen, avoiding: [CGPoint(x: 100, y: 800)])
        #expect(frame == CGRect(x: 560, y: 12, width: 320, height: 62))
    }

    @Test func movesAwayFromAClickUnderIt() {
        let frame = WorkflowControlsController.frame(size: size, in: screen, avoiding: [CGPoint(x: 720, y: 40)])
        #expect(frame.origin == CGPoint(x: 560, y: 875 - 12 - 62))
    }

    @Test func avoidsTheWholePathOfADrag() {
        // A drag from the left edge to the right edge, along the bottom: only the top is clear.
        let drag = WorkflowAction.drag(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 1440, y: 50), button: .left, duration: 1, modifiers: 0)
        let frame = WorkflowControlsController.frame(size: size, in: screen, avoiding: drag.points)
        #expect(frame.minY > 700)
    }

    @Test func picksTheLeastCoveredSpotWhenNoneIsClear() {
        let spots = [CGPoint(x: 720, y: 40), CGPoint(x: 720, y: 840), CGPoint(x: 1300, y: 40), CGPoint(x: 1300, y: 40),
                     CGPoint(x: 100, y: 40), CGPoint(x: 1300, y: 840), CGPoint(x: 100, y: 840)]
        // Bottom right has two clicks; every other spot has one, and bottom center comes first.
        let frame = WorkflowControlsController.frame(size: size, in: screen, avoiding: spots)
        #expect(frame.origin == CGPoint(x: 560, y: 12))
    }

    @Test func samplesDragsAndSkipsKeys() {
        let drag = WorkflowAction.drag(from: .zero, to: CGPoint(x: 80, y: 0), button: .left, duration: 0.5, modifiers: 0)
        #expect(drag.points.first == .zero)
        #expect(drag.points.last == CGPoint(x: 80, y: 0))
        #expect(drag.points.count == 11)
        #expect(WorkflowAction.key(code: 0, modifiers: 0, characters: "a").points.isEmpty)
    }
}

struct WorkflowBuilderPauseTests {
    @Test func ignoresInputWhilePausedAndDoesNotCountThePause() {
        var builder = WorkflowBuilder(start: 0)
        builder.add(.key(code: 0, modifiers: 0, characters: "a"), at: 0.5)
        builder.pause(at: 1)
        builder.add(.key(code: 1, modifiers: 0, characters: "s"), at: 5)
        builder.resume(at: 31)
        builder.add(.key(code: 2, modifiers: 0, characters: "d"), at: 32)
        let steps = builder.finish()
        #expect(steps.count == 2)
        // 0.5 s before the pause and 1 s after it: the 30 s paused aren't a wait.
        #expect(abs(steps[1].delay - 1.5) < 0.0001)
    }

    @Test func dropsAButtonHeldWhenPausing() {
        var builder = WorkflowBuilder(start: 0)
        builder.add(.mouseDown(.zero, .left, clickCount: 1, modifiers: 0), at: 0.1)
        builder.pause(at: 0.2)
        builder.resume(at: 0.3)
        builder.add(.mouseUp(.zero, .left), at: 0.4)
        builder.add(.mouseDown(CGPoint(x: 9, y: 9), .left, clickCount: 1, modifiers: 0), at: 0.5)
        builder.add(.mouseUp(CGPoint(x: 9, y: 9), .left), at: 0.6)
        let steps = builder.finish()
        #expect(steps.map(\.action) == [.click(at: CGPoint(x: 9, y: 9), button: .left, count: 1, modifiers: 0)])
    }
}

struct WorkflowStoreRenameTests {
    @Test @MainActor func renamesAndKeepsTheNameWhenBlank() {
        let url = FileManager.default.temporaryDirectory.appending(path: "wiggle-tests-\(UUID().uuidString)/workflows.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = WorkflowStore(url: url)
        let workflow = Workflow(name: "Workflow 1", steps: [WorkflowStep(delay: 0, action: .key(code: 0, modifiers: 0, characters: "a"))])
        store.add(workflow)
        store.rename(workflow.id, to: "  Cold email  ")
        store.rename(workflow.id, to: "   ")
        #expect(WorkflowStore(url: url).workflows.map(\.name) == ["Cold email"])
    }
}

struct WorkflowEditingTests {
    private let shift = CGEventFlags.maskShift.rawValue
    private var keys: KeyLayout {
        KeyLayout(keys: ["h": (4, 0), "i": (34, 0), "H": (4, shift), " ": (49, 0), "!": (18, shift)])
    }

    private func key(_ characters: String, code: UInt16 = 0, modifiers: UInt64 = 0, delay: TimeInterval = 0.1) -> WorkflowStep {
        WorkflowStep(delay: delay, action: .key(code: code, modifiers: modifiers, characters: characters))
    }

    private let click = WorkflowStep(delay: 1, action: .click(at: CGPoint(x: 5, y: 5), button: .left, count: 1, modifiers: 0))

    @Test func typingKeepsItsCorrectionsAndLineBreaks() {
        let steps = [key("a"), key("x"), key("", code: 51), key("b"), key("\r", code: 36, modifiers: shift), key("c")]
        let groups = WorkflowStepGroup.groups(for: steps)
        #expect(groups.count == 1)
        #expect(groups[0].text == "ab\nc")
        #expect(groups[0].title == "Type “ab c”")
    }

    @Test func aBackspaceBeforeAnyTypingIsItsOwnStep() {
        let groups = WorkflowStepGroup.groups(for: [key("", code: 51), key("a")])
        #expect(groups.map(\.title) == ["Press ⌫", "Type “a”"])
    }

    @Test func repeatedKeysShareARow() {
        let escape = key("\u{1b}", code: 53)
        let groups = WorkflowStepGroup.groups(for: [escape, escape, escape, click, escape])
        #expect(groups.map(\.title) == ["Press Esc ×3", "Click at 5, 5", "Press Esc"])
        #expect(groups[0].range == 0..<3)
    }

    @Test func typesWithTheLayoutsKeysAtTheRecordedRhythm() {
        let steps = keys.typing("Hi!\n😀", after: 2, rhythm: [0.1, 0.3])
        #expect(steps.map(\.action) == [
            .key(code: 4, modifiers: shift, characters: "H"),
            .key(code: 34, modifiers: 0, characters: "i"),
            .key(code: 18, modifiers: shift, characters: "!"),
            .key(code: 36, modifiers: shift, characters: "\n"),
            .text("😀"),
        ])
        #expect(steps.map(\.delay) == [2, 0.1, 0.3, 0.1, 0.3])
        #expect(WorkflowStepGroup.groups(for: steps).map(\.text) == ["Hi!\n😀"])
    }

    @Test func readsChangesOutOfAReply() {
        let reply = """
            Here's a version for Sarah.

            <type step="3">
            Hi Sarah,
            Loved your post.
            </type>
            <remove steps="5-7, 9"/>
            Want it shorter?
            """
        let (prose, edits) = WorkflowEdits.parse(reply)
        #expect(edits.texts == [3: "Hi Sarah,\nLoved your post."])
        #expect(edits.removed == [5, 6, 7, 9])
        #expect(prose == "Here's a version for Sarah.\n\nWant it shorter?")
    }

    @Test func hidesATagStillStreamingIn() {
        let (prose, edits) = WorkflowEdits.parse("Sure, here it is. <type step=\"3\">Hi Sar")
        #expect(prose == "Sure, here it is.")
        #expect(edits.isEmpty)
    }

    @Test func appliesChangesByStepNumber() throws {
        // 1 click, 2 "ab" typed, 3 Esc ×2, 4 Return.
        let escape = key("\u{1b}", code: 53)
        let steps = [click, key("a", delay: 0.5), key("b", delay: 0.2), escape, escape, key("\r", code: 36)]
        let edits = WorkflowEdits(texts: [2: "hi"], removed: [3])
        let changed = try #require(edits.applied(to: steps, keys: keys))
        #expect(WorkflowStepGroup.groups(for: changed).map(\.title) == ["Click at 5, 5", "Type “hi”", "Press ↩"])
        #expect(changed[1].delay == 0.5)  // the wait before typing is kept
        #expect(changed[2].delay == 0.2)  // and typed at the recorded rhythm
    }

    @Test func refusesChangesThatDontFit() {
        let steps = [click, key("a")]
        #expect(WorkflowEdits(texts: [1: "no"]).applied(to: steps, keys: keys) == nil)  // step 1 is a click
        #expect(WorkflowEdits(removed: [3]).applied(to: steps, keys: keys) == nil)  // there's no step 3
        #expect(WorkflowEdits(removed: [1, 2]).applied(to: steps, keys: keys) == nil)  // nothing left
    }

    @Test func promptNumbersTheStepsLikeTheEdits() {
        let workflow = Workflow(name: "Note", steps: [click, key("a"), key("\r", code: 36, modifiers: shift), key("\"")])
        let prompt = Prompts.editWorkflow(workflow, request: "Make it longer")
        #expect(prompt.contains("1. Click at 5, 5\n2. Type \"a\\n\\\"\""))
        #expect(prompt.hasSuffix("Make it longer"))
    }
}

struct WorkflowStoreEditedCopyTests {
    @Test @MainActor func keepsTheOriginalAndReplacesOneEditedCopy() {
        let url = FileManager.default.temporaryDirectory.appending(path: "wiggle-tests-\(UUID().uuidString)/workflows.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let typed = { (text: String) in [WorkflowStep(delay: 0, action: .text(text))] }
        let store = WorkflowStore(url: url)
        let original = Workflow(name: "Cold message", steps: typed("Hi"))
        store.add(original)

        let first = store.saveEdited(original, steps: typed("Hi Sarah"))
        let second = store.saveEdited(original, steps: typed("Hi Ahmed"))
        #expect(first.id == second.id)
        #expect(second.name == "Cold message (edited)")

        let reloaded = WorkflowStore(url: url).workflows
        #expect(reloaded.count == 2)
        #expect(reloaded.first { $0.id == original.id }?.steps == typed("Hi"))
        #expect(reloaded.first { $0.id == second.id }?.steps == typed("Hi Ahmed"))

        // Changing the edited copy itself changes it in place.
        store.saveEdited(second, steps: typed("Hi Ahmed!"))
        #expect(WorkflowStore(url: url).workflows.count == 2)
    }
}

struct WorkflowEditProblemTests {
    @Test func explainsChangesThatDontFit() {
        let steps = [
            WorkflowStep(delay: 0, action: .click(at: CGPoint(x: 862, y: 696), button: .left, count: 1, modifiers: 0)),
            WorkflowStep(delay: 0, action: .text("hi")),
        ]
        let edits = WorkflowEdits(texts: [1: "Hello", 2: "Hey"], removed: [5])
        #expect(edits.problems(in: steps) == [
            1: "Step 1 is “Click at 862, 696”, which doesn't type anything.",
            5: "There's no step 5.",
        ])
        #expect(edits.applied(to: steps, keys: KeyLayout(keys: [:])) == nil)
        #expect(WorkflowEdits(texts: [2: "Hey"]).problems(in: steps).isEmpty)
        #expect(WorkflowEdits(removed: [1]).problems(in: []) == [1: "There's no step 1."])
    }

    @Test func promptListsTheStepsThatType() {
        let workflow = Workflow(name: "Note", steps: [
            WorkflowStep(delay: 0, action: .click(at: .zero, button: .left, count: 1, modifiers: 0)),
            WorkflowStep(delay: 0, action: .text("hi")),
        ])
        #expect(Prompts.editWorkflow(workflow, request: "x").contains("Only steps 2 type anything"))
    }
}

struct APIKeyCheckTests {
    @Test func catchesPasteMistakesBeforeAsking() {
        #expect(APIKeyCheck.formatProblem("sk-ant-api03-abc", for: .anthropic) == nil)
        #expect(APIKeyCheck.formatProblem("sk-ant-api03-a\nbc", for: .anthropic)?.contains("spaces or line breaks") == true)
        #expect(APIKeyCheck.formatProblem("sk-ant-admin01-abc", for: .anthropic)?.contains("Admin key") == true)
        #expect(APIKeyCheck.formatProblem("sk-proj-abc", for: .anthropic)?.contains("start with “sk-ant-”") == true)
        #expect(APIKeyCheck.formatProblem("sk-ant-api03-abc", for: .openai)?.contains("Anthropic key") == true)
        #expect(APIKeyCheck.formatProblem("sk-proj-abc", for: .openai) == nil)
    }
}
