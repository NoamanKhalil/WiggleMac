import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Menu bar app: no Dock icon, even when run unbundled via `swift run`.
    app.setActivationPolicy(.accessory)
    app.run()
}
