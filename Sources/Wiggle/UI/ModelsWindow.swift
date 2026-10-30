import AppKit
import SwiftUI

@MainActor
@Observable
final class ModelsModel {
    struct Download {
        var fraction: Double?
        var status: String
        var task: Task<Void, Never>?
    }

    private let settings = Settings.shared
    private var client: OllamaClient { OllamaClient(host: settings.ollamaHost) }

    private(set) var active: ModelChoice
    private(set) var appleUnavailableReason: String?
    private(set) var ollamaRunning = false
    private(set) var installed: [OllamaModel] = []
    private(set) var downloads: [String: Download] = [:]
    var error: String?

    var customModelName = ""

    private(set) var hasAnthropicKey: Bool
    private(set) var hasOpenAIKey: Bool
    var anthropicKeyInput = ""
    var openAIKeyInput = ""
    var anthropicModel: String {
        didSet { settings.anthropicModel = anthropicModel }
    }
    var openAIModel: String {
        didSet { settings.openAIModel = openAIModel }
    }

    init() {
        active = settings.model
        hasAnthropicKey = Keychain.read(.anthropic) != nil
        hasOpenAIKey = Keychain.read(.openai) != nil
        anthropicModel = settings.anthropicModel
        openAIModel = settings.openAIModel
    }

    var availableCatalog: [CatalogModel] {
        let names = Set(installed.map(\.name))
        return CatalogModel.all.filter { !names.contains($0.name) && !names.contains("\($0.name):latest") }
    }

    func refresh() async {
        appleUnavailableReason = AppleChatSession.unavailableReason
        ollamaRunning = await client.isRunning()
        installed = ollamaRunning ? (try? await client.installedModels()) ?? [] : []
    }

    func use(_ choice: ModelChoice) {
        var choice = choice
        if case .openai(let name) = choice {
            choice = .openai(name.trimmingCharacters(in: .whitespaces))
        }
        settings.model = choice
        active = choice
    }

    /// What to switch to when the active model goes away: Apple Intelligence if it's ready,
    /// otherwise another downloaded local model.
    private func fallback(excluding name: String? = nil) -> ModelChoice {
        if appleUnavailableReason == nil { return .apple }
        if let local = installed.first(where: { $0.name != name }) { return .ollama(local.name) }
        return .ollama(Settings.defaultOllamaModel)
    }

    // MARK: Ollama

    func download(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, downloads[name] == nil else { return }
        error = nil
        downloads[name] = Download(status: "Starting…")
        let task = Task {
            do {
                try await client.pull(name) { fraction, status in
                    self.downloads[name]?.fraction = fraction
                    self.downloads[name]?.status = status
                }
                downloads[name] = nil
                await refresh()
            } catch is CancellationError {
                downloads[name] = nil
            } catch {
                downloads[name] = nil
                if !Task.isCancelled {
                    self.error = "Couldn't download \(name): \(error.localizedDescription)"
                }
            }
        }
        downloads[name]?.task = task
    }

    func cancelDownload(_ name: String) {
        downloads[name]?.task?.cancel()
        downloads[name] = nil
    }

    func delete(_ model: OllamaModel) async {
        do {
            try await client.delete(model.name)
            if active == .ollama(model.name) {
                use(fallback(excluding: model.name))
            }
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func openOllama() {
        let app = URL(fileURLWithPath: "/Applications/Ollama.app")
        if FileManager.default.fileExists(atPath: app.path) {
            Task {
                _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: .init())
                try? await Task.sleep(for: .seconds(2))
                await refresh()
            }
        } else {
            NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
        }
    }

    // MARK: API keys

    func saveAnthropicKey() {
        Keychain.write(anthropicKeyInput.trimmingCharacters(in: .whitespacesAndNewlines), for: .anthropic)
        anthropicKeyInput = ""
        hasAnthropicKey = Keychain.read(.anthropic) != nil
    }

    func removeAnthropicKey() {
        Keychain.write("", for: .anthropic)
        hasAnthropicKey = false
        if case .anthropic = active { use(fallback()) }
    }

    func saveOpenAIKey() {
        Keychain.write(openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines), for: .openai)
        openAIKeyInput = ""
        hasOpenAIKey = Keychain.read(.openai) != nil
    }

    func removeOpenAIKey() {
        Keychain.write("", for: .openai)
        hasOpenAIKey = false
        if case .openai = active { use(fallback()) }
    }
}

@MainActor
final class ModelsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let model = ModelsModel()
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 460, height: 580),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Wiggle Models"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ModelsView(model: model))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct ModelsView: View {
    @Bindable var model: ModelsModel
    @State private var pendingDelete: OllamaModel?

    var body: some View {
        Form {
            Section {
                LabeledContent("Wiggle is using", value: model.active.displayName)
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Built in") {
                ModelRow(
                    title: "Apple Intelligence",
                    subtitle: model.appleUnavailableReason ?? "Apple's on-device model. Private, fast, understands screenshots.",
                    badges: ["On device", "Vision"],
                    isActive: model.active == .apple
                ) {
                    UseButton(isActive: model.active == .apple) { model.use(.apple) }
                        .disabled(model.appleUnavailableReason != nil)
                }
            }

            localSection
            downloadSection
            anthropicSection
            openAISection
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .font(.callout)
        .frame(minWidth: 420, minHeight: 400)
        .task { await model.refresh() }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let target = pendingDelete {
                    Task { await model.delete(target) }
                }
            }
        } message: {
            Text("This removes the model from your Mac. You can download it again later.")
        }
    }

    @ViewBuilder
    private var localSection: some View {
        Section {
            if !model.ollamaRunning {
                HStack {
                    Label("Ollama isn't running. It runs local models on your Mac.", systemImage: "exclamationmark.circle")
                    Spacer()
                    Button("Open Ollama") { model.openOllama() }
                }
            } else if model.installed.isEmpty {
                Text("No local models yet. Download one below.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.installed) { local in
                let choice = ModelChoice.ollama(local.name)
                ModelRow(
                    title: local.name,
                    subtitle: ByteCountFormatter.string(fromByteCount: local.size, countStyle: .file),
                    badges: local.supportsVision ? ["Vision"] : [],
                    isActive: model.active == choice
                ) {
                    UseButton(isActive: model.active == choice) { model.use(choice) }
                    Button {
                        pendingDelete = local
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete from this Mac")
                }
            }
        } header: {
            HStack {
                Text("On this Mac (Ollama)")
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
        }
    }

    @ViewBuilder
    private var downloadSection: some View {
        Section {
            ForEach(model.availableCatalog) { item in
                ModelRow(
                    title: item.title,
                    subtitle: "\(item.summary) \(Self.size(item.sizeMB))",
                    badges: item.vision ? ["Vision"] : [],
                    isActive: false
                ) {
                    DownloadControl(name: item.name, model: model)
                }
                .disabled(!model.ollamaRunning)
            }
            HStack {
                TextField("Any Ollama model, e.g. mistral:7b", text: $model.customModelName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.download(model.customModelName) }
                DownloadControl(name: model.customModelName.trimmingCharacters(in: .whitespaces), model: model)
                    .disabled(model.customModelName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .disabled(!model.ollamaRunning)
        } header: {
            Text("Download more models")
        } footer: {
            Text("Models run entirely on your Mac. “Vision” models can see screenshots; others read the text in them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var anthropicSection: some View {
        Section {
            if model.hasAnthropicKey {
                HStack {
                    Label("API key saved in your Keychain", systemImage: "key.fill")
                    Spacer()
                    Button("Remove", role: .destructive) { model.removeAnthropicKey() }
                }
                Picker("Model", selection: $model.anthropicModel) {
                    ForEach(AnthropicChatSession.models) { Text($0.name).tag($0.id) }
                }
                let choice = ModelChoice.anthropic(model.anthropicModel)
                HStack {
                    Spacer()
                    UseButton(isActive: model.active == choice) { model.use(choice) }
                }
            } else {
                HStack {
                    SecureField("sk-ant-…", text: $model.anthropicKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.saveAnthropicKey() }
                    Button("Save") { model.saveAnthropicKey() }
                        .disabled(model.anthropicKeyInput.isEmpty)
                }
            }
        } header: {
            Text("Claude (your Anthropic API key)")
        } footer: {
            Text("Questions and screenshots are sent to Anthropic and billed to your key. Get a key at console.anthropic.com.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var openAISection: some View {
        Section {
            if model.hasOpenAIKey {
                HStack {
                    Label("API key saved in your Keychain", systemImage: "key.fill")
                    Spacer()
                    Button("Remove", role: .destructive) { model.removeOpenAIKey() }
                }
                TextField("Model", text: $model.openAIModel)
                let choice = ModelChoice.openai(model.openAIModel)
                HStack {
                    Spacer()
                    UseButton(isActive: model.active == choice) { model.use(choice) }
                        .disabled(model.openAIModel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                HStack {
                    SecureField("sk-…", text: $model.openAIKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.saveOpenAIKey() }
                    Button("Save") { model.saveOpenAIKey() }
                        .disabled(model.openAIKeyInput.isEmpty)
                }
            }
        } header: {
            Text("OpenAI (your API key)")
        } footer: {
            Text("Questions and screenshots are sent to OpenAI and billed to your key. Get a key at platform.openai.com.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func size(_ megabytes: Int) -> String {
        megabytes >= 1000 ? String(format: "%.1f GB", Double(megabytes) / 1000) : "\(megabytes) MB"
    }
}

private struct ModelRow<Actions: View>: View {
    let title: String
    let subtitle: String
    let badges: [String]
    let isActive: Bool
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title).fontWeight(isActive ? .semibold : .regular)
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            actions
        }
    }
}

private struct UseButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        if isActive {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("In use")
        } else {
            Button("Use", action: action)
        }
    }
}

private struct DownloadControl: View {
    let name: String
    let model: ModelsModel

    var body: some View {
        if let download = model.downloads[name] {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    if let fraction = download.fraction {
                        ProgressView(value: fraction).frame(width: 80)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(download.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 80, alignment: .trailing)
                }
                Button {
                    model.cancelDownload(name)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Cancel download")
            }
        } else {
            Button {
                model.download(name)
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .help("Download")
        }
    }
}
