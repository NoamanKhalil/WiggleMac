import AppKit
import ServiceManagement
import SwiftUI

/// Wiggle's Settings window: General, Models and Texting tabs. The tabs sit in the window's content,
/// not in a toolbar, so the forms below can't scroll up under them.
@MainActor
final class SettingsWindowController {
    enum Tab: Hashable {
        case general, models, texting
    }

    @MainActor
    @Observable
    final class Selection {
        var tab: Tab = .general
    }

    private let general: GeneralSettings
    private let texting: Texting
    private let selection = Selection()
    private var window: NSWindow?

    init(general: GeneralSettings, texting: Texting) {
        self.general = general
        self.texting = texting
    }

    func show(_ tab: Tab = .general) {
        if window == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 520, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Wiggle Settings"
            window.isReleasedWhenClosed = false
            window.contentMinSize = CGSize(width: 480, height: 480)
            window.contentView = NSHostingView(rootView: SettingsView(
                selection: selection, general: general, models: ModelsModel(), texting: texting
            ))
            window.center()
            self.window = window
        }
        general.refresh()
        selection.tab = tab
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @Bindable var selection: SettingsWindowController.Selection
    let general: GeneralSettings
    let models: ModelsModel
    let texting: Texting

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralView(settings: general)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsWindowController.Tab.general)
            ModelsView(model: models)
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag(SettingsWindowController.Tab.models)
            TextingView(texting: texting)
                .tabItem { Label("Texting", systemImage: "message") }
                .tag(SettingsWindowController.Tab.texting)
        }
        .padding(.top, 8)
    }
}

/// The General tab's settings. The menu bar's quick switches change them through here too, so both agree.
@MainActor
@Observable
final class GeneralSettings {
    @ObservationIgnored private let settings = Settings.shared
    /// Applies a change to the wiggle detector.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var checkForUpdates: (() -> Void)?

    var isEnabled: Bool {
        didSet {
            settings.isEnabled = isEnabled
            onChange?()
        }
    }

    var sensitivity: Sensitivity {
        didSet {
            settings.sensitivity = sensitivity
            onChange?()
        }
    }

    private(set) var launchesAtLogin = false
    private(set) var launchError: String?
    /// Login items need the app bundle; a `swift run` build has none.
    let canLaunchAtLogin = Bundle.main.bundleIdentifier != nil

    init() {
        isEnabled = settings.isEnabled
        sensitivity = settings.sensitivity
        refresh()
    }

    /// Login items can change in System Settings while Wiggle runs.
    func refresh() {
        launchesAtLogin = canLaunchAtLogin && SMAppService.mainApp.status == .enabled
    }

    func setLaunchesAtLogin(_ on: Bool) {
        launchError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchError = error.localizedDescription
        }
        refresh()
    }
}

private struct GeneralView: View {
    @Bindable var settings: GeneralSettings

    var body: some View {
        Form {
            Section {
                Toggle("Wiggle your mouse to ask", isOn: $settings.isEnabled)
                Picker("Sensitivity", selection: $settings.sensitivity) {
                    ForEach(Sensitivity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.isEnabled)
            } footer: {
                Text("Higher sensitivity needs fewer, shorter shakes. Lower it if Wiggle opens when you didn't mean it to.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open Wiggle when you log in", isOn: Binding(
                    get: { settings.launchesAtLogin },
                    set: { settings.setLaunchesAtLogin($0) }
                ))
                .disabled(!settings.canLaunchAtLogin)
                if let error = settings.launchError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let checkForUpdates = settings.checkForUpdates {
                    HStack {
                        Text("Updates")
                        Spacer()
                        Button("Check for Updates…", action: checkForUpdates)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
