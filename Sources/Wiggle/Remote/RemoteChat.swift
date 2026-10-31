import Foundation

/// Texting Wiggle. A few words are commands (list, change, save and run workflows); anything else goes
/// to the model, about the workflow being changed if there is one. A run starts only after "yes",
/// since it clicks and types on this Mac.
@MainActor
final class RemoteChat {
    struct Controls {
        var isPlaying: () -> Bool
        var isPaused: () -> Bool
        var run: (Workflow) -> Void
        var togglePause: () -> Void
        var stop: () -> Void
        /// Why a run can't start right now (no Accessibility permission, a locked screen), if it can't.
        var blocker: () -> String?
    }

    struct Reply: Equatable {
        var text: String
        /// The workflow a "yes" just started, so the bridge can say when it's done.
        var started: String?
    }

    static let help = """
        Text me anything to chat. Or:
        • workflows: list them
        • change <name or number>: then tell me what to change, e.g. who a message is for
        • save: keep the changes as "<name> (edited)"
        • run <name or number>: I'll ask you to reply yes first
        • pause, resume, stop, status
        • done: stop changing a workflow
        """

    private let store: WorkflowStore
    private let controls: Controls
    private let makeSession: () throws -> ChatSession
    private let keys: () -> KeyLayout
    private let now: () -> Date

    private var session: ChatSession?
    private var editingID: Workflow.ID?
    /// The last reply's changes, and the workflow as it was when they were asked for.
    private var proposal: (workflow: Workflow, edits: WorkflowEdits)?
    private var pendingRun: (id: Workflow.ID, until: Date)?
    private var savedID: Workflow.ID?

    init(store: WorkflowStore, controls: Controls, makeSession: @escaping () throws -> ChatSession,
         keys: @escaping () -> KeyLayout, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.controls = controls
        self.makeSession = makeSession
        self.keys = keys
        self.now = now
    }

    func handle(_ message: String) async -> Reply {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = text.split(separator: " ", maxSplits: 1)
        let command = words.first.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) } ?? ""
        let argument = words.count > 1 ? String(words[1]).trimmingCharacters(in: .whitespaces) : ""

        // A yes counts only as the very next message.
        let pending = pendingRun
        pendingRun = nil

        switch command {
        case "help", "?", "":
            return Reply(text: Self.help)
        case "workflows", "list":
            return Reply(text: list())
        case "run":
            return Reply(text: askToRun(argument))
        case "yes", "y":
            return confirm(pending)
        case "no", "cancel":
            return Reply(text: pending == nil ? "Okay." : "Okay, not running it.")
        case "pause", "resume":
            guard controls.isPlaying() else { return Reply(text: "Nothing's running.") }
            if controls.isPaused() == (command == "pause") { return Reply(text: command == "pause" ? "It's already paused." : "It's already running.") }
            controls.togglePause()
            return Reply(text: command == "pause" ? "Paused. Text resume to carry on." : "Carrying on.")
        case "stop":
            guard controls.isPlaying() else { return Reply(text: "Nothing's running.") }
            controls.stop()
            return Reply(text: "Stopped.")
        case "status":
            return Reply(text: controls.isPlaying() ? (controls.isPaused() ? "A workflow is paused." : "A workflow is running.") : "Nothing's running.")
        case "change", "edit":
            return Reply(text: startChanging(argument))
        case "save":
            return Reply(text: save())
        case "done":
            editingID = nil
            proposal = nil
            return Reply(text: "Okay, done changing it.")
        default:
            return Reply(text: await ask(text))
        }
    }

    // MARK: - Workflows

    private func list() -> String {
        guard !store.workflows.isEmpty else { return "No workflows yet. Record one in Wiggle on your Mac." }
        let lines = store.workflows.enumerated().map { "\($0.offset + 1). \($0.element.name) (\($0.element.summary))" }
        return lines.joined(separator: "\n")
    }

    /// By number from `list`, exact name, or the one name that contains it. Otherwise why not, as a reply.
    private func find(_ argument: String) -> Result<Workflow, Unfound> {
        let workflows = store.workflows
        if argument.isEmpty { return .failure(Unfound("Which one? Text workflows to see them.")) }
        if let number = Int(argument), workflows.indices.contains(number - 1) { return .success(workflows[number - 1]) }
        let name = argument.lowercased()
        if let exact = workflows.first(where: { $0.name.lowercased() == name }) { return .success(exact) }
        let matches = workflows.indices.filter { workflows[$0].name.lowercased().contains(name) }
        switch matches.count {
        case 0: return .failure(Unfound("I can't find “\(argument)”. Text workflows to see them."))
        case 1: return .success(workflows[matches[0]])
        default:
            let options = matches.map { "\($0 + 1). \(workflows[$0].name)" }.joined(separator: "\n")
            return .failure(Unfound("Which one? Text its number:\n\(options)"))
        }
    }

    private struct Unfound: Error {
        let reply: String
        init(_ reply: String) { self.reply = reply }
    }

    private func askToRun(_ argument: String) -> String {
        let found = argument.isEmpty && savedID != nil
            ? store.workflows.first { $0.id == savedID }.map { .success($0) } ?? find(argument)
            : find(argument)
        let workflow: Workflow
        switch found {
        case .success(let match): workflow = match
        case .failure(let unfound): return unfound.reply
        }
        if controls.isPlaying() { return "A workflow is already running. Text stop first." }
        pendingRun = (workflow.id, now().addingTimeInterval(120))
        var text = "Run “\(workflow.name)” (\(workflow.summary))? It will click and type on your Mac."
        let typed = WorkflowStepGroup.groups(for: workflow.steps).compactMap(\.text).filter { !$0.isEmpty }
        if !typed.isEmpty {
            text += " It types:\n" + typed.map { "• " + ($0.count > 160 ? String($0.prefix(159)) + "…" : $0) }.joined(separator: "\n")
        }
        return text + "\nReply yes to start."
    }

    private func confirm(_ pending: (id: Workflow.ID, until: Date)?) -> Reply {
        guard let pending, pending.until > now() else {
            return Reply(text: pending == nil ? "There's nothing waiting for a yes." : "That was a while ago. Text run again.")
        }
        guard let workflow = store.workflows.first(where: { $0.id == pending.id }) else { return Reply(text: "That workflow is gone.") }
        if controls.isPlaying() { return Reply(text: "A workflow is already running. Text stop first.") }
        if let blocker = controls.blocker() { return Reply(text: blocker) }
        controls.run(workflow)
        return Reply(text: "Running “\(workflow.name)”. Text pause, resume or stop.", started: workflow.name)
    }

    private func startChanging(_ argument: String) -> String {
        let workflow: Workflow
        switch find(argument) {
        case .success(let match): workflow = match
        case .failure(let unfound): return unfound.reply
        }
        editingID = workflow.id
        proposal = nil
        session = nil
        return "Changing “\(workflow.name)”. Tell me what to change, like who a message is for. Changes are saved as a copy; the original stays as recorded."
    }

    private func save() -> String {
        guard let proposal else { return "There are no changes to save yet." }
        guard let current = store.workflows.first(where: { $0.id == proposal.workflow.id }), current.steps == proposal.workflow.steps else {
            return "The workflow changed since then. Ask for the change again."
        }
        guard let steps = proposal.edits.applied(to: current.steps, keys: keys()) else {
            return "Those changes don't fit the workflow. Ask again, saying which step to change."
        }
        let saved = store.saveEdited(current, steps: steps)
        savedID = saved.id
        self.proposal = nil
        return "Saved “\(saved.name)”. Text run to run it."
    }

    // MARK: - Model

    private func ask(_ text: String) async -> String {
        let workflow = store.workflows.first { $0.id == editingID }
        let reply: String
        do {
            let session = try self.session ?? makeSession()
            self.session = session
            var latest = ""
            for try await partial in session.send(workflow.map { Prompts.editWorkflow($0, request: text) } ?? text, screenshot: nil) {
                latest = partial
            }
            reply = latest
        } catch {
            return "I couldn't get an answer: \(error.localizedDescription)"
        }
        guard let workflow else { return reply }

        let (prose, edits) = WorkflowEdits.parse(reply)
        guard !edits.isEmpty else { return prose }
        let problems = edits.problems(in: workflow.steps)
        if !problems.isEmpty {
            proposal = nil
            let reasons = problems.keys.sorted().compactMap { problems[$0] }.joined(separator: "\n")
            return [prose, "Those changes don't fit:\n\(reasons)\nAsk again, saying which step to change."]
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        proposal = (workflow, edits)
        let groups = WorkflowStepGroup.groups(for: workflow.steps)
        var parts = [prose]
        for step in edits.texts.keys.sorted() where !edits.removed.contains(step) {
            parts.append("Step \(step) will type:\n\(edits.texts[step] ?? "")")
        }
        for step in edits.removed.sorted() {
            parts.append("Removes step \(step): \(groups[step - 1].title)")
        }
        parts.append("Text save to keep this as “\(workflow.name) (edited)”, or tell me what to change.")
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
