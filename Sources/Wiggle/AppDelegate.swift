import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let detector = WiggleDetector()
    private let glow = CursorGlowController()
    private let modelsWindow = ModelsWindowController()

    private var statusItem: NSStatusItem?
    private var panel: PromptPanelController?
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        detector.isEnabled = settings.isEnabled
        detector.sensitivity = settings.sensitivity
        detector.onWiggle = { [weak self] point in self?.toggle(at: point) }
        detector.start()

        // A display coming or going (or the Mac sleeping) can strand the panel off screen.
        let close: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.dismiss() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: close
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: close
        )
    }

    // MARK: - Panel

    /// A wiggle opens the panel, and the next wiggle closes it.
    private func toggle(at point: CGPoint) {
        if let panel {
            panel.dismiss()
        } else {
            present(at: point)
        }
    }

    private func present(at point: CGPoint) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost

        let controller = PromptPanelController(near: point)
        controller.model.onBusyChanged = { [weak self] busy in
            self?.glow.isThinking = busy
        }
        controller.onDismiss = { [weak self] in self?.panelDidDismiss() }
        panel = controller

        NSApp.activate()
        controller.show()
        glow.show(at: point)
    }

    private func panelDidDismiss() {
        panel = nil
        glow.isThinking = false
        glow.hide()

        // Escape returns focus to where the user was; clicking another app already moved it.
        if NSApp.isActive {
            previousApp?.activate()
        }
        previousApp = nil
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "Wiggle")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = settings.isEnabled ? "Wiggle your mouse to ask" : "Wiggle detection is off"
        menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Model: \(settings.model.displayName)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(item("Wiggle to Ask", action: #selector(toggleEnabled), checked: settings.isEnabled))
        menu.addItem(item("Models…", action: #selector(showModels)))

        let sensitivityMenu = NSMenu()
        for level in Sensitivity.allCases {
            let entry = item(level.title, action: #selector(selectSensitivity(_:)), checked: settings.sensitivity == level)
            entry.representedObject = level.rawValue
            sensitivityMenu.addItem(entry)
        }
        menu.addItem(submenu("Wiggle Sensitivity", sensitivityMenu))

        if Bundle.main.bundleIdentifier != nil {
            menu.addItem(item("Launch at Login", action: #selector(toggleLaunchAtLogin),
                              checked: SMAppService.mainApp.status == .enabled))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Wiggle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, action: Selector, checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        detector.isEnabled = settings.isEnabled
    }

    @objc private func showModels() {
        modelsWindow.show()
    }

    @objc private func selectSensitivity(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let level = Sensitivity(rawValue: raw) else { return }
        settings.sensitivity = level
        detector.sensitivity = level
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
