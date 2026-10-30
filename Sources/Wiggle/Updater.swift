import AppKit
import Sparkle

/// Automatic updates through Sparkle. Off unless the build has a feed URL (`SUFeedURL`), which
/// release builds get from WIGGLE_FEED_URL; dev builds have none and never check.
@MainActor
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    override init() {
        super.init()
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        guard let feed, !feed.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // Wiggle lives in the menu bar, so scheduled update alerts shouldn't steal focus from the app in use.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
