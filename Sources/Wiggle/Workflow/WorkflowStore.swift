import Foundation

/// Saved workflows, newest first, in ~/Library/Application Support/Wiggle/workflows.json.
@MainActor
@Observable
final class WorkflowStore {
    static let shared = WorkflowStore()

    private(set) var workflows: [Workflow] = []
    private let url: URL

    init(url: URL = WorkflowStore.defaultURL) {
        self.url = url
        load()
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Wiggle/workflows.json")
    }

    var nextDefaultName: String {
        let taken = Set(workflows.map(\.name))
        var number = workflows.count + 1
        while taken.contains("Workflow \(number)") { number += 1 }
        return "Workflow \(number)"
    }

    func add(_ workflow: Workflow) {
        workflows.insert(workflow, at: 0)
        save()
    }

    func update(_ workflow: Workflow) {
        guard let index = workflows.firstIndex(where: { $0.id == workflow.id }) else { return }
        workflows[index] = workflow
        save()
    }

    /// Saves changed steps to the edited copy of `workflow`, "<name> (edited)", and leaves the original
    /// as recorded. Each original has one edited copy, replaced every time; an edited copy changes itself.
    @discardableResult
    func saveEdited(_ workflow: Workflow, steps: [WorkflowStep]) -> Workflow {
        let existing = workflow.editedFrom == nil ? workflows.first { $0.editedFrom == workflow.id } : workflow
        guard var copy = existing else {
            let copy = Workflow(name: "\(workflow.name) (edited)", steps: steps, editedFrom: workflow.id)
            add(copy)
            return copy
        }
        copy.steps = steps
        update(copy)
        return copy
    }

    /// A blank name keeps the old one.
    func rename(_ id: Workflow.ID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = workflows.firstIndex(where: { $0.id == id }), workflows[index].name != name
        else { return }
        workflows[index].name = name
        save()
    }

    func delete(_ id: Workflow.ID) {
        workflows.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            workflows = try JSONDecoder().decode([Workflow].self, from: data)
        } catch {
            // Keep an unreadable file instead of overwriting it on the next save.
            let aside = url.deletingLastPathComponent().appending(path: "workflows-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(workflows).write(to: url, options: .atomic)
        } catch {
            NSLog("Wiggle couldn't save workflows: \(error.localizedDescription)")
        }
    }
}
