import AppKit
import AVFoundation
import Speech

@MainActor
@Observable
final class PromptModel {
    enum Stage {
        case choosing
        case chat
    }

    enum Choice {
        case chat
        case screenshot
        case voice
    }

    struct Turn: Identifiable {
        let id = UUID()
        let prompt: String
        let screenshot: Screenshot?
        var response = ""
        var error: String?
    }

    struct Notice {
        let text: String
        var settingsURL: URL?
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
        }
    }

    /// Keyboard shortcuts on the chooser. Returns true when handled.
    func handleChooserKey(_ characters: String) -> Bool {
        switch characters.lowercased() {
        case "c", "1", "\r": choose(.chat)
        case "s", "2": choose(.screenshot)
        case "v", "3": choose(.voice)
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
        attachment = nil
        input = ""
        notice = nil
        turns.append(Turn(prompt: prompt, screenshot: screenshot))
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
                for try await text in session.send(prompt, screenshot: screenshot) {
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
