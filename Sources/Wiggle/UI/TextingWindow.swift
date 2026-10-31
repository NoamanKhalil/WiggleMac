import AppKit
import SwiftUI

/// The Texting tab of Settings.
struct TextingView: View {
    @Bindable var texting: Texting
    @State private var showsLog = false

    var body: some View {
        Form {
            Section {
                Toggle("Text Wiggle from iMessage", isOn: Binding(get: { texting.isOn }, set: { texting.setOn($0) }))
                if texting.isOn { status }
            } footer: {
                Text("Text your Photon number to chat with Wiggle, change workflows and run them. Only texts from your number get through, and a run waits for you to reply yes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Project ID", text: $texting.projectID, prompt: Text("From your project's Settings"))
                    .onSubmit { texting.restartBridge() }
                if texting.hasSecret {
                    HStack {
                        Label(texting.isBeta ? "API key saved in your Keychain" : "Project secret saved in your Keychain", systemImage: "key.fill")
                        Spacer()
                        Button("Remove", role: .destructive) { texting.removeSecret() }
                    }
                } else {
                    HStack {
                        SecureField(texting.isBeta ? "API key" : "Project secret", text: $texting.secretInput,
                                    prompt: Text(texting.isBeta ? "pho_sk_…" : "Paste the secret"))
                            .onSubmit { texting.saveSecret() }
                        Button("Save") { texting.saveSecret() }
                            .disabled(texting.secretInput.isEmpty)
                    }
                }
                TextField("Your number", text: $texting.allowedSender, prompt: Text("+1 555 123 4567"))
                    .onSubmit { texting.restartBridge() }
                HStack {
                    if texting.isBeta {
                        Link("Open app.beta.photon.codes", destination: URL(string: "https://app.beta.photon.codes")!)
                    } else {
                        Link("Open app.photon.codes", destination: URL(string: "https://app.photon.codes")!)
                    }
                    Spacer()
                    if texting.isOn {
                        Button("Apply") { texting.restartBridge() }
                            .disabled(texting.missing != nil)
                    }
                }
            } header: {
                Text("Photon")
            } footer: {
                Text(texting.isBeta
                     ? "Photon 2.0 project: create an API key on the project's API keys page, with permission to read and send messages. Texts and replies go through Photon's servers; your workflows stay on this Mac."
                     : "Find the project ID and secret in your project's Settings. Projects on app.beta.photon.codes (IDs starting pho_prj_) use an API key instead. Texts and replies go through Photon's servers; your workflows stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("What you can text") {
                VStack(alignment: .leading, spacing: 4) {
                    command("anything", "chat with the model chosen under Models")
                    command("workflows", "list them")
                    command("change <name>", "then say what to change, e.g. who it's for")
                    command("save", "keep it as “<name> (edited)”")
                    command("run <name>", "Wiggle shows what it'll type; reply yes to start")
                    command("pause · resume · stop · status · help", "")
                }
                .font(.callout)
            }

            if !texting.bridge.log.isEmpty {
                Section {
                    DisclosureGroup("Bridge log", isExpanded: $showsLog) {
                        ScrollView {
                            Text(texting.bridge.log.suffix(60).joined(separator: "\n"))
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var status: some View {
        if let error = texting.serverError {
            Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        } else if let missing = texting.missing {
            Label(missing, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
        } else {
            switch texting.bridge.status {
            case .stopped:
                Label("Not connected", systemImage: "circle").foregroundStyle(.secondary)
            case .starting:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to Photon…").foregroundStyle(.secondary)
                }
            case .waiting(let sender):
                Label("Connected. Waiting for texts from \(sender).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let reason):
                HStack(alignment: .firstTextBaseline) {
                    Label(reason, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Try Again") { texting.restartBridge() }
                }
            }
        }
    }

    private func command(_ name: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name).font(.system(.callout, design: .monospaced))
            if !detail.isEmpty {
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
