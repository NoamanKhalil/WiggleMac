import AVFoundation
import Speech

/// Listens to the microphone and transcribes on-device. Finishes on its own after a pause.
@MainActor
@Observable
final class SpeechListener {
    enum Failure: LocalizedError {
        case notAuthorized
        case unavailable
        case noMicrophone
        case audio(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "Wiggle needs Microphone and Speech Recognition permission to listen. Allow them in System Settings."
            case .unavailable:
                "Speech recognition isn't available right now."
            case .noMicrophone:
                "Wiggle can't find a microphone. Connect one, or choose an input in System Settings › Sound."
            case .audio(let message):
                "Couldn't start the microphone: \(message)"
            }
        }
    }

    static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!

    private(set) var isListening = false
    private(set) var transcript = ""

    /// Called once with the final transcript (possibly empty) when listening ends on its own.
    var onFinish: ((String) -> Void)?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?

    /// Silence after speech that ends the utterance, and the wait for any speech at all.
    private let pauseToFinish: Duration = .seconds(1.6)
    private let waitForSpeech: Duration = .seconds(8)

    /// Nonisolated: TCC calls back on a background queue, so the callback must not be main-actor isolated.
    nonisolated static func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() throws {
        guard !isListening else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        else { throw Failure.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { throw Failure.unavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // With no input device the format is empty, and installing a tap on it raises an exception.
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Failure.noMicrophone }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.audioTap(feeding: request))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw Failure.audio(error.localizedDescription)
        }

        transcript = ""
        isListening = true
        self.engine = engine
        self.request = request
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(for: self))
        scheduleFinish(after: waitForSpeech)
    }

    // Speech and AVAudio call these back on their own threads. Closures written inside this
    // main-actor class would be main-actor isolated and trap there, so they're built in
    // nonisolated functions instead.

    /// Runs on the audio thread; appending buffers to the request is thread-safe.
    private nonisolated static func audioTap(feeding request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let request = request
        return { buffer, _ in request.append(buffer) }
    }

    private nonisolated static func resultHandler(for listener: SpeechListener) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak listener] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                listener?.handle(text: text, isFinal: isFinal, failed: failed)
            }
        }
    }

    /// Stops and delivers whatever was heard.
    func finish() {
        guard isListening else { return }
        let text = transcript
        stop()
        onFinish?(text)
    }

    /// Stops without delivering anything.
    func stop() {
        silenceTimer?.cancel()
        silenceTimer = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        isListening = false
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard isListening else { return }
        if let text, text != transcript {
            transcript = text
            scheduleFinish(after: pauseToFinish)
        }
        if isFinal || failed {
            finish()
        }
    }

    private func scheduleFinish(after delay: Duration) {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }
}
