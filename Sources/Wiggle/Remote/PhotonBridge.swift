import Foundation

/// Runs the Photon bridge (photon-bridge.mjs, bundled in the app) with the Mac's Node, passing it the
/// Photon credentials in its environment, never in a file. It quits when Wiggle does: its stdin is a
/// pipe from Wiggle, and closing that ends it even if Wiggle crashes.
@MainActor
@Observable
final class PhotonBridge {
    enum Status: Equatable {
        case stopped
        case starting
        case waiting(for: String)
        case failed(String)
    }

    private(set) var status: Status = .stopped
    /// The bridge's recent output, newest last.
    private(set) var log: [String] = []

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: Pipe?
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var logFile: FileHandle?

    /// The log, also kept on disk for troubleshooting; it starts over each time the bridge does.
    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Wiggle/photon-bridge.log")
    }

    static var script: URL? { Bundle.main.url(forResource: "photon-bridge", withExtension: "mjs") }

    /// Node from Homebrew or the official installer, else wherever the login shell finds it.
    static func findNode() -> URL? {
        for path in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] where FileManager.default.isExecutableFile(atPath: path) {
            return URL(filePath: path)
        }
        let shell = Process()
        shell.executableURL = URL(filePath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v node"]
        let output = Pipe()
        shell.standardOutput = output
        shell.standardError = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return nil }
        shell.waitUntilExit()
        let path = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : URL(filePath: path)
    }

    func start(projectID: String, secret: String, allowedSender: String) {
        stop()
        log = []
        guard let script = Self.script else {
            status = .failed("This build of Wiggle doesn't include the bridge. Build it with make app after npm install in photon-bridge.")
            return
        }
        guard let node = Self.findNode() else {
            status = .failed("Texting needs Node.js 22 or later. Install it from nodejs.org or with Homebrew (brew install node), then turn texting on again.")
            return
        }

        let process = Process()
        process.executableURL = node
        process.arguments = [script.path]
        process.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:\(node.deletingLastPathComponent().path)",
            // Photon 2.0 (Beta) projects read the PHOTON_ names, others the SPECTRUM_ ones.
            "SPECTRUM_PROJECT_ID": projectID,
            "SPECTRUM_PROJECT_SECRET": secret,
            "PHOTON_PROJECT_ID": projectID,
            "PHOTON_PROJECT_API_KEY": secret,
            "WIGGLE_ALLOWED_SENDER": allowedSender,
            "WIGGLE_MANAGED": "1",
            "TUICHAT_QUIET": "1",
        ]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.received(text) }
        }
        process.terminationHandler = { [weak self] ended in
            let code = ended.terminationStatus
            Task { @MainActor in self?.ended(code: code) }
        }

        stopping = false
        status = .starting
        try? FileManager.default.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        logFile = try? FileHandle(forWritingTo: Self.logURL)
        do {
            try process.run()
            self.process = process
            self.input = input
        } catch {
            status = .failed("Couldn't start the bridge: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let process else { return }
        stopping = true
        process.terminate()
        try? input?.fileHandleForWriting.close()
        self.process = nil
        input = nil
        status = .stopped
    }

    private func received(_ text: String) {
        for line in text.split(whereSeparator: \.isNewline).map(String.init) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            log.append(line)
            logFile?.write(Data("\(Date.now.formatted(.iso8601)) \(line)\n".utf8))
            if let range = line.range(of: "Waiting for texts from ") {
                status = .waiting(for: String(line[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ". ")))
            }
        }
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    private func ended(code: Int32) {
        process = nil
        input = nil
        guard !stopping else { return }
        // The bridge explains itself in lines starting "Error: " (bad credentials, no network).
        if let reason = log.last(where: { $0.hasPrefix("Error: ") }) {
            status = .failed(String(reason.dropFirst("Error: ".count)))
        } else {
            status = .failed("The bridge stopped (exit code \(code)). See the log below.")
        }
    }
}
