import Foundation

/// Texting Wiggle from iMessage: the 127.0.0.1 server the bridge talks to, and the bridge itself once
/// the Photon details are in. Off until turned on.
@MainActor
@Observable
final class Texting {
    let bridge = PhotonBridge()
    @ObservationIgnored let server = RemoteServer()
    @ObservationIgnored private let settings = Settings.shared

    private(set) var isOn: Bool
    var projectID: String {
        didSet { settings.photonProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    var allowedSender: String {
        didSet { settings.textingFrom = allowedSender.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    private(set) var hasSecret: Bool
    var secretInput = ""
    private(set) var serverError: String?

    init() {
        isOn = settings.allowsTexting
        projectID = settings.photonProjectID
        allowedSender = settings.textingFrom
        hasSecret = Keychain.contains(.photonSecret)
    }

    /// Photon 2.0 (Beta) projects, at app.beta.photon.codes, take an API key instead of a project secret.
    var isBeta: Bool { projectID.trimmingCharacters(in: .whitespaces).hasPrefix("pho_prj_") }

    /// What's still needed before the bridge can start.
    var missing: String? {
        if projectID.trimmingCharacters(in: .whitespaces).isEmpty || !hasSecret {
            return isBeta ? "Add your Photon project ID and API key." : "Add your Photon project ID and secret."
        }
        if !Self.isValidSender(allowedSender) { return "Add the phone number (or Apple ID email) you'll text from." }
        return nil
    }

    /// At least 10 digits, or an email address.
    static func isValidSender(_ sender: String) -> Bool {
        let trimmed = sender.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("@") { return trimmed.split(separator: "@").count == 2 }
        return trimmed.filter(\.isNumber).count >= 10
    }

    func setOn(_ on: Bool) {
        isOn = on
        settings.allowsTexting = on
        if on { start() } else { stop() }
    }

    /// Starts what's switched on; called at launch too.
    func start() {
        guard isOn else { return }
        serverError = nil
        do {
            try server.start()
        } catch {
            serverError = "Couldn't start: \(error.localizedDescription)"
            return
        }
        restartBridge()
    }

    func stop() {
        bridge.stop()
        server.stop()
    }

    /// After a detail changes, or to try again after a failure.
    func restartBridge() {
        guard isOn, missing == nil, let secret = Keychain.read(.photonSecret) else {
            bridge.stop()
            return
        }
        bridge.start(projectID: settings.photonProjectID, secret: secret, allowedSender: settings.textingFrom)
    }

    func saveSecret() {
        let secret = secretInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { return }
        Keychain.write(secret, for: .photonSecret)
        secretInput = ""
        hasSecret = Keychain.contains(.photonSecret)
        restartBridge()
    }

    func removeSecret() {
        Keychain.write("", for: .photonSecret)
        hasSecret = false
        bridge.stop()
    }
}
