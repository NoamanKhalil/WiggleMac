import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let detector = WiggleDetector()
    private let glow = CursorGlowController()
    private let general = GeneralSettings()
    private let recorder = WorkflowRecorder()
    private let player = WorkflowPlayer()
    private let controls = WorkflowControlsController()
    private let texting = Texting()
    private lazy var settingsWindow = SettingsWindowController(general: general, texting: texting)
    private lazy var remoteChat = RemoteChat(
        store: .shared,
        controls: RemoteChat.Controls(
            isPlaying: { [unowned self] in player.isPlaying },
            isPaused: { [unowned self] in player.isPaused },
            run: { [unowned self] workflow in run(workflow, times: 1) },
            togglePause: { [unowned self] in player.togglePause() },
            stop: { [unowned self] in player.stop() },
            blocker: { Self.runBlocker() }
        ),
        makeSession: { try LLM.makeSession(for: Settings.shared.model) },
        keys: { .current() }
    )

    private var statusItem: NSStatusItem?
    private var panel: PromptPanelController?
    private var previousApp: NSRunningApplication?
    private var updater: Updater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        updater = Updater()
        setUpStatusItem()
        NSApp.mainMenu = Self.makeMainMenu()
        texting.server.handler = { [weak self] request in
            await self?.handleRemote(request) ?? RemoteServer.Response(status: 503, json: [:])
        }
        texting.start()

        detector.isEnabled = settings.isEnabled
        detector.sensitivity = settings.sensitivity
        general.onChange = { [weak self] in
            guard let self else { return }
            detector.isEnabled = general.isEnabled
            detector.sensitivity = general.sensitivity
        }
        if updater?.isAvailable == true {
            general.checkForUpdates = { [weak self] in self?.updater?.checkForUpdates() }
        }
        detector.onWiggle = { [weak self] point in self?.toggle(at: point) }
        detector.start()

        player.onFinish = { [weak self] in self?.workflowDidFinish() }
        player.onPauseChanged = { [weak self] in self?.workflowPauseDidChange() }
        recorder.onPauseChanged = { [weak self] in self?.updateStatusIcon() }

        // A display coming or going (or the Mac sleeping) can strand the panel off screen,
        // and moves the spots a workflow clicks on.
        let close: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel?.dismiss()
                self?.player.stop()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: close
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: close
        )
    }

    // MARK: - Panel

    /// A wiggle opens the panel, and the next wiggle closes it. While recording a workflow it
    /// stops the recording; while a workflow runs (or is paused) it stops the run.
    private func toggle(at point: CGPoint) {
        if recorder.isRecording {
            finishRecording(at: point)
        } else if player.isPlaying {
            player.stop()
        } else if let panel {
            panel.dismiss()
        } else {
            present(at: point)
        }
    }

    /// `review` opens straight onto a just-recorded workflow, ready to name and save.
    private func present(at point: CGPoint, review: [WorkflowStep]? = nil) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost

        let controller = PromptPanelController(near: point)
        controller.model.onBusyChanged = { [weak self] busy in
            self?.glow.isThinking = busy
        }
        controller.onDismiss = { [weak self] in self?.panelDidDismiss() }
        controller.model.onRecordWorkflow = { [weak self] in self?.startRecording() }
        controller.model.onRunWorkflow = { [weak self] workflow, times in self?.run(workflow, times: times) }
        if let review { controller.model.review(review) }
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

    // MARK: - Workflows

    private func startRecording() {
        panel?.dismiss()  // hands focus back to the app the user was in
        recorder.start()
        controls.show(recorder) { [weak self] in self?.finishRecording(at: NSEvent.mouseLocation) }
        glow.show(at: NSEvent.mouseLocation, recording: true)
        updateStatusIcon()
    }

    private func finishRecording(at point: CGPoint) {
        let steps = recorder.stop()
        controls.hide()
        glow.hide()
        updateStatusIcon()
        present(at: point, review: steps)
    }

    private func run(_ workflow: Workflow, times: Int) {
        guard !workflow.steps.isEmpty else { return }
        panel?.dismiss()
        // Give the app the user was in a moment to come forward before the first click or keystroke.
        player.play(workflow, times: times, after: .milliseconds(350))
        controls.show(player, running: workflow)
        glow.show(at: NSEvent.mouseLocation)
        glow.isThinking = true
        updateStatusIcon()
    }

    /// Paused, the ring slows down: nothing is happening until the run resumes.
    private func workflowPauseDidChange() {
        glow.isThinking = !player.isPaused
        updateStatusIcon()
    }

    private func workflowDidFinish() {
        controls.hide()
        glow.isThinking = false
        glow.hide()
        updateStatusIcon()
    }

    @objc private func togglePauseRecording() {
        recorder.togglePause()
    }

    @objc private func stopRecordingFromMenu() {
        finishRecording(at: NSEvent.mouseLocation)
    }

    @objc private func togglePauseWorkflow() {
        player.togglePause()
    }

    @objc private func stopWorkflow() {
        player.stop()
    }

    private func updateStatusIcon() {
        let (symbol, tint): (String, NSColor?) =
            recorder.isPaused ? ("pause.circle.fill", .systemRed)
            : recorder.isRecording ? ("record.circle.fill", .systemRed)
            : player.isPaused ? ("pause.circle.fill", nil)
            : player.isPlaying ? ("play.circle.fill", nil)
            : ("cursorarrow.motionlines", nil)
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Wiggle")
        statusItem?.button?.contentTintColor = tint
    }

    /// Never shown (Wiggle has no menu bar of its own), but ⌘C, ⌘V, ⌘A and ⌘Z in text fields
    /// only work through an Edit menu.
    private static func makeMainMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let menu = NSMenu()
        let app = NSMenu(title: "Wiggle")
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        let appItem = NSMenuItem(title: "Wiggle", action: nil, keyEquivalent: "")
        appItem.submenu = app
        menu.addItem(appItem)
        menu.addItem(editItem)
        return menu
    }

    // MARK: - Texting (Photon bridge)

    @objc private func showSettings() {
        settingsWindow.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        texting.stop()
    }

    private func handleRemote(_ request: RemoteServer.Request) async -> RemoteServer.Response {
        switch (request.method, request.path) {
        case ("POST", "/message"):
            guard let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let text = json["text"] as? String
            else { return RemoteServer.Response(status: 400, json: ["error": "Send {\"text\": …}."]) }
            let reply = await remoteChat.handle(text)
            var body: [String: Any] = ["reply": reply.text]
            if let started = reply.started { body["started"] = started }
            return RemoteServer.Response(status: 200, json: body)
        case ("GET", "/status"):
            return RemoteServer.Response(status: 200, json: ["running": player.isPlaying, "paused": player.isPaused])
        default:
            return RemoteServer.Response(status: 404, json: ["error": "Not found."])
        }
    }

    /// Replayed clicks and keys need Accessibility permission, and go nowhere on a locked screen.
    private static func runBlocker() -> String? {
        if !Accessibility.isTrusted {
            return "Wiggle needs Accessibility permission to run workflows. Turn it on in System Settings → Privacy & Security → Accessibility on your Mac."
        }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        if session?["CGSSessionScreenIsLocked"] as? Bool == true {
            return "Your Mac's screen is locked, so Wiggle can't click or type. Unlock it, then text run again."
        }
        return nil
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

        if recorder.isRecording {
            menu.addItem(item(recorder.isPaused ? "Resume Recording" : "Pause Recording", action: #selector(togglePauseRecording)))
            menu.addItem(item("Stop Recording", action: #selector(stopRecordingFromMenu)))
            menu.addItem(.separator())
        } else if player.isPlaying {
            menu.addItem(item(player.isPaused ? "Resume Workflow" : "Pause Workflow", action: #selector(togglePauseWorkflow)))
            menu.addItem(item("Stop Workflow", action: #selector(stopWorkflow)))
            menu.addItem(.separator())
        }

        let status = settings.isEnabled ? "Wiggle your mouse to ask" : "Wiggle detection is off"
        menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Model: \(settings.model.displayName)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(item("Wiggle to Ask", action: #selector(toggleEnabled), checked: general.isEnabled))
        let settingsItem = item("Settings…", action: #selector(showSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Wiggle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, action: Selector, checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        return item
    }

    @objc private func toggleEnabled() {
        general.isEnabled.toggle()
    }
}
