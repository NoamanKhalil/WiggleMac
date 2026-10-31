import AppKit
import AVFoundation
import Speech

@MainActor
@Observable
final class PromptModel {
    enum Stage {
        case choosing
        case chat
        case workflows
        case saveWorkflow
    }

    enum Choice {
        case chat
        case screenshot
        case voice
        case workflow
    }

    struct Turn: Identifiable {
        let id = UUID()
        let prompt: String
        let screenshot: Screenshot?
        /// The workflow being changed, as it was when this was asked: the reply's step numbers refer to it.
        var workflow: Workflow?
        var response = ""
        var error: String?
        /// The edited copy the reply's changes were saved to.
        var savedAs: Workflow.ID?
    }

    struct Notice {
        let text: String
        var settingsURL: URL?
        /// Runs before System Settings opens, e.g. to add Wiggle to a privacy list.
        var beforeSettings: (@MainActor () -> Void)?
    }

    var stage: Stage = .choosing
    var input = ""
    var turns: [Turn] = []
    /// Screenshot waiting to go out with the next message.
    var attachment: Screenshot?
    /// Where each saved screenshot went, by screenshot id.
    private(set) var savedScreenshots: [UUID: URL] = [:]
    var notice: Notice?
    private(set) var isGenerating = false
    private(set) var isCapturing = false
    private(set) var modelName: String
    let listener = SpeechListener()

    /// While true, losing key focus (to a permission prompt) shouldn't close the panel.
    private(set) var isAwaitingSystemPrompt = false

    // Workflows
    let workflows = WorkflowStore.shared
    /// A finished recording waiting to be named and saved.
    private(set) var recording: [WorkflowStep] = []
    var workflowName = ""
    var repeatCount = 1
    var onRecordWorkflow: (() -> Void)?
    var onRunWorkflow: ((Workflow, Int) -> Void)?
    /// The workflow the chat is changing.
    private(set) var editingWorkflowID: Workflow.ID?
    var editingWorkflow: Workflow? { workflows.workflows.first { $0.id == editingWorkflowID } }

    var onBusyChanged: ((Bool) -> Void)?
    var captureScreen: (() async throws -> Screenshot)?
    var requestFocus: (() -> Void)?

    private var session: ChatSession?
    private var task: Task<Void, Never>?
    /// Bumped by every send and cancel, so a stopped reply finishing late can't reset a newer one.
    private var generation = 0
    private var isSaving = false

    init() {
        modelName = Settings.shared.model.displayName
        listener.onFinish = { [weak self] text in self?.handleSpeech(text) }
    }

    // MARK: - Chooser

    func choose(_ choice: Choice) {
        stage = .chat
        switch choice {
        case .chat: break
        case .screenshot: Task { await takeScreenshot() }
        case .voice: Task { await startListening() }
        case .workflow: stage = .workflows
        }
    }

    /// Keyboard shortcuts on the chooser. Returns true when handled.
    func handleChooserKey(_ characters: String) -> Bool {
        switch characters.lowercased() {
        case "c", "1", "\r": choose(.chat)
        case "s", "2": choose(.screenshot)
        case "v", "3": choose(.voice)
        case "w", "4": choose(.workflow)
        default: return false
        }
        return true
    }

    // MARK: - Screenshot

    func takeScreenshot() async {
        guard let captureScreen, !isCapturing else { return }
        notice = nil
        isCapturing = true
        updateBusy()
        isAwaitingSystemPrompt = true
        do {
            attachment = try await captureScreen()
        } catch let error as ScreenCapture.CaptureError {
            notice = Notice(text: error.localizedDescription,
                            settingsURL: error == .permissionDenied ? ScreenCapture.settingsURL : nil)
        } catch {
            notice = Notice(text: "Couldn't take a screenshot: \(error.localizedDescription)")
        }
        isAwaitingSystemPrompt = false
        isCapturing = false
        updateBusy()
        requestFocus?()
    }

    /// Saves the full-resolution screenshot next to the Mac's own screenshots. Nothing is saved otherwise.
    func save(_ screenshot: Screenshot) async {
        guard savedScreenshots[screenshot.id] == nil, !isSaving else { return }
        notice = nil
        isSaving = true
        isAwaitingSystemPrompt = true
        do {
            savedScreenshots[screenshot.id] = try await ScreenshotSaver.save(screenshot)
        } catch CocoaError.fileWriteNoPermission {
            notice = Notice(text: "Wiggle needs permission to save to \(ScreenshotSaver.folder().lastPathComponent). Allow it in System Settings, then try again.",
                            settingsURL: ScreenshotSaver.privacySettingsURL)
        } catch {
            notice = Notice(text: "Couldn't save the screenshot: \(error.localizedDescription)")
        }
        isAwaitingSystemPrompt = false
        isSaving = false
        requestFocus?()
    }

    func revealSaved(_ screenshot: Screenshot) {
        guard let url = savedScreenshots[screenshot.id] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Workflows

    func recordWorkflow() {
        guard checkAccessibility() else { return }
        onRecordWorkflow?()
    }

    func run(_ workflow: Workflow, times: Int? = nil) {
        guard checkAccessibility() else { return }
        onRunWorkflow?(workflow, times ?? repeatCount)
    }

    func renameWorkflow(_ workflow: Workflow, to name: String) {
        workflows.rename(workflow.id, to: name)
    }

    /// Opens the chat on `workflow`: what's asked changes what it types, or removes steps.
    func changeWithChat(_ workflow: Workflow) {
        editingWorkflowID = workflow.id
        notice = nil
        stage = .chat
    }

    func stopChangingWorkflow() {
        editingWorkflowID = nil
    }

    /// Saves the changes a reply proposes to the workflow's edited copy. Refused if the workflow changed
    /// since it was asked, since the reply's step numbers would point at the wrong steps.
    func applyChanges(from turn: Turn) {
        guard let index = turns.firstIndex(where: { $0.id == turn.id }), let asked = turn.workflow,
              let workflow = workflows.workflows.first(where: { $0.id == asked.id })
        else { return }
        guard workflow.steps == asked.steps else {
            notice = Notice(text: "The workflow changed since this reply. Ask again to change it as it is now.")
            return
        }
        guard let steps = WorkflowEdits.parse(turn.response).edits.applied(to: asked.steps, keys: .current()) else {
            notice = Notice(text: "Those changes don't match the workflow's steps. Ask again.")
            return
        }
        turns[index].savedAs = workflows.saveEdited(workflow, steps: steps).id
    }

    func savedWorkflow(for turn: Turn) -> Workflow? {
        workflows.workflows.first { $0.id == turn.savedAs }
    }

    func runSavedWorkflow(for turn: Turn) {
        guard let workflow = savedWorkflow(for: turn) else { return }
        run(workflow, times: 1)
    }

    func deleteWorkflow(_ workflow: Workflow) {
        workflows.delete(workflow.id)
    }

    /// Shows a just-finished recording so it can be named and saved.
    func review(_ steps: [WorkflowStep]) {
        recording = steps
        workflowName = workflows.nextDefaultName
        stage = .saveWorkflow
    }

    func removeSteps(_ range: Range<Int>) {
        recording.removeSubrange(range)
    }

    func saveRecording() {
        guard !recording.isEmpty else { return }
        let name = workflowName.trimmingCharacters(in: .whitespacesAndNewlines)
        workflows.add(Workflow(name: name.isEmpty ? workflows.nextDefaultName : name, steps: recording))
        recording = []
        stage = .workflows
    }

    func discardRecording() {
        recording = []
        stage = .workflows
    }

    private func checkAccessibility() -> Bool {
        if Accessibility.isTrusted { return true }
        notice = Notice(text: "Workflows need Accessibility permission to record and replay clicks and typing. Turn on Wiggle in System Settings, then try again.",
                        settingsURL: Accessibility.settingsURL,
                        beforeSettings: { Accessibility.requestAccess() })
        return false
    }

    // MARK: - Voice

    func toggleListening() {
        if listener.isListening {
            listener.finish()
        } else {
            Task { await startListening() }
        }
    }

    func startListening() async {
        notice = nil
        isAwaitingSystemPrompt = true
        let authorized = await SpeechListener.requestAuthorization()
        isAwaitingSystemPrompt = false
        requestFocus?()

        guard authorized else {
            notice = Notice(text: SpeechListener.Failure.notAuthorized.localizedDescription,
                            settingsURL: SpeechListener.microphoneSettingsURL)
            return
        }
        do {
            try listener.start()
        } catch {
            notice = Notice(text: error.localizedDescription)
        }
    }

    /// Live transcript shown in the input field while listening.
    func transcriptChanged(_ text: String) {
        if listener.isListening { input = text }
    }

    private func handleSpeech(_ text: String) {
        let command = VoiceCommand.parse(text)
        input = command.question
        guard command.wantsScreenshot else {
            if !input.isEmpty { submit() }
            return
        }
        Task {
            await takeScreenshot()
            guard attachment != nil else { return }
            if command.question.isEmpty {
                // "Screenshot" on its own: capture, then listen for the question.
                await startListening()
            } else {
                submit()
            }
        }
    }

    // MARK: - Chat

    func submit() {
        listener.stop()
        guard !isGenerating, !isCapturing else { return }

        var prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty {
            guard attachment != nil else { return }
            prompt = Prompts.describeScreen
        }
        let screenshot = attachment
        let workflow = editingWorkflow
        let message = workflow.map { Prompts.editWorkflow($0, request: prompt) } ?? prompt
        attachment = nil
        input = ""
        notice = nil
        turns.append(Turn(prompt: prompt, screenshot: screenshot, workflow: workflow))
        let index = turns.count - 1

        let session: ChatSession
        do {
            session = try self.session ?? LLM.makeSession(for: Settings.shared.model)
            self.session = session
            modelName = session.modelName
        } catch {
            turns[index].error = error.localizedDescription
            return
        }

        isGenerating = true
        updateBusy()
        generation += 1
        let current = generation
        task = Task {
            do {
                for try await text in session.send(message, screenshot: screenshot) {
                    turns[index].response = text
                }
            } catch {
                // Stopping can surface as URLError.cancelled rather than CancellationError: not worth showing.
                if !Task.isCancelled { turns[index].error = error.localizedDescription }
            }
            guard current == generation else { return }
            isGenerating = false
            updateBusy()
        }
    }

    /// The panel is closing: keep a recording that wasn't explicitly discarded.
    func close() {
        if stage == .saveWorkflow { saveRecording() }
        cancel()
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        listener.stop()
        isGenerating = false
        updateBusy()
    }

    private func updateBusy() {
        onBusyChanged?(isGenerating || isCapturing)
    }
}
