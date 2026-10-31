import AppKit
import SwiftUI

/// Borderless floating panel that can take keyboard focus.
final class PromptPanel: NSPanel {
    var onCancel: (() -> Void)?
    /// Gets unhandled key presses first; return true to swallow them.
    var onKey: ((String) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if let characters = event.charactersIgnoringModifiers, onKey?(characters) == true { return }
        super.keyDown(with: event)
    }
}

@MainActor
final class PromptPanelController: NSObject, NSWindowDelegate {
    static let size = CGSize(width: 360, height: 380)

    let model = PromptModel()
    var onDismiss: (() -> Void)?

    private let panel: PromptPanel

    init(near point: CGPoint) {
        let placement = Self.placement(near: point)
        panel = PromptPanel(
            contentRect: placement.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.dismiss() }
        panel.onKey = { [weak self] characters in
            guard let model = self?.model, model.stage == .choosing else { return false }
            return model.handleChooserKey(characters)
        }

        model.captureScreen = { try await ScreenCapture.captureScreen(containing: NSEvent.mouseLocation) }
        model.requestFocus = { [weak self] in
            NSApp.activate()
            self?.panel.makeKeyAndOrderFront(nil)
        }

        panel.contentView = NSHostingView(
            rootView: PromptView(model: model, growsUp: placement.growsUp, leansLeft: placement.leansLeft)
        )
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        model.close()
        panel.delegate = nil
        panel.orderOut(nil)
        onDismiss?()
        onDismiss = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        // Permission prompts take focus briefly; anything else closes the panel.
        guard !model.isAwaitingSystemPrompt else { return }
        dismiss()
    }

    /// Places the panel below-right of the pointer, flipping up or left when there isn't room.
    private static func placement(near point: CGPoint) -> (frame: CGRect, growsUp: Bool, leansLeft: Bool) {
        let screen = ScreenLocator.screen(containing: point)
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: size)
        let gap: CGFloat = 14

        var x = point.x + gap
        let leansLeft = x + size.width > visible.maxX
        if leansLeft { x = point.x - gap - size.width }
        x = min(max(x, visible.minX), visible.maxX - size.width)

        var y = point.y - gap - size.height
        let growsUp = y < visible.minY
        if growsUp { y = point.y + gap }
        y = min(max(y, visible.minY), visible.maxY - size.height)

        return (CGRect(x: x, y: y, width: size.width, height: size.height), growsUp, leansLeft)
    }
}

// MARK: - Views

private struct PromptView: View {
    let model: PromptModel
    let growsUp: Bool
    let leansLeft: Bool

    var body: some View {
        VStack(spacing: 0) {
            if growsUp { Spacer(minLength: 0) }
            Group {
                switch model.stage {
                case .choosing: ChooserCard(model: model)
                case .chat: ChatCard(model: model)
                case .workflows: WorkflowCard(model: model)
                case .saveWorkflow: SaveWorkflowCard(model: model)
                }
            }
            .frame(maxWidth: .infinity, alignment: leansLeft ? .trailing : .leading)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            if !growsUp { Spacer(minLength: 0) }
        }
        .animation(.snappy(duration: 0.2), value: model.stage)
        .frame(width: PromptPanelController.size.width, height: PromptPanelController.size.height)
    }
}

/// Glass card with the multicolor border that spins while busy.
struct CardBackground: ViewModifier {
    let isBusy: Bool

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                TimelineView(.animation(paused: !isBusy)) { context in
                    let degrees = context.date.timeIntervalSinceReferenceDate * 240
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.sweep(angle: .degrees(degrees)), lineWidth: isBusy ? 1.5 : 1)
                        .opacity(isBusy ? 1 : 0.7)
                }
            }
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            .padding(8)
    }
}

private struct ChooserCard: View {
    let model: PromptModel

    var body: some View {
        HStack(spacing: 2) {
            ChoiceTile(icon: "bubble.left.fill", title: "Chat", key: "C") { model.choose(.chat) }
            ChoiceTile(icon: "camera.viewfinder", title: "Screenshot", key: "S") { model.choose(.screenshot) }
            ChoiceTile(icon: "mic.fill", title: "Voice", key: "V") { model.choose(.voice) }
            ChoiceTile(icon: "record.circle", title: "Workflow", key: "W") { model.choose(.workflow) }
        }
        .padding(4)
        .fixedSize()
        .modifier(CardBackground(isBusy: false))
    }
}

private struct ChoiceTile: View {
    let icon: String
    let title: String
    let key: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.sweep(angle: .degrees(isHovered ? 90 : 0)))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) (\(key))")
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

private struct ChatCard: View {
    @Bindable var model: PromptModel

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.turns.isEmpty {
                transcript
                Divider().opacity(0.5)
            }
            if let notice = model.notice {
                NoticeRow(notice: notice)
            }
            if let attachment = model.attachment {
                AttachmentChip(model: model, screenshot: attachment) { model.attachment = nil }
            }
            if let workflow = model.editingWorkflow {
                WorkflowChip(workflow: workflow) { model.stopChangingWorkflow() }
            }
            inputRow
            footer
        }
        .frame(width: PromptPanelController.size.width - 16)
        .modifier(CardBackground(isBusy: model.isGenerating || model.isCapturing || model.listener.isListening))
        .onAppear { focused = true }
        .onChange(of: model.listener.transcript) { _, text in model.transcriptChanged(text) }
    }

    private var placeholder: String {
        if model.listener.isListening { return "Listening… (say “screenshot”)" }
        if model.isCapturing { return "Capturing…" }
        if model.attachment != nil { return "Ask about this screen…" }
        if model.editingWorkflow != nil { return "Who's it for, or what should change?" }
        return model.turns.isEmpty ? "Ask anything…" : "Ask a follow-up…"
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.turns) { turn in
                        TurnView(model: model, turn: turn, isStreaming: model.isGenerating && turn.id == model.turns.last?.id)
                            .id(turn.id)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: model.turns.last?.response) {
                if let id = model.turns.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.sweep(angle: .degrees(0)))
            TextField(placeholder, text: $model.input)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { model.submit() }

            if model.isCapturing {
                ProgressView().controlSize(.mini)
            } else {
                IconButton(symbol: "camera.viewfinder", help: "Attach a screenshot of your screen") {
                    Task { await model.takeScreenshot() }
                }
            }
            IconButton(symbol: model.listener.isListening ? "waveform.circle.fill" : "mic",
                       help: model.listener.isListening ? "Stop listening" : "Speak your question",
                       tint: model.listener.isListening ? .red : nil) {
                model.toggleListening()
            }
            .symbolEffect(.pulse, isActive: model.listener.isListening)
            if model.isGenerating {
                IconButton(symbol: "stop.circle.fill", help: "Stop generating") { model.cancel() }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack {
            Text(model.modelName)
            Spacer()
            Text("↩ send · esc")
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct NoticeRow: View {
    let notice: PromptModel.Notice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(notice.text)
                .fixedSize(horizontal: false, vertical: true)
            if let url = notice.settingsURL {
                Spacer(minLength: 4)
                Button("Settings") {
                    notice.beforeSettings?()
                    NSWorkspace.shared.open(url)
                }
                    .controlSize(.mini)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}

private struct AttachmentChip: View {
    let model: PromptModel
    let screenshot: Screenshot
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: screenshot.nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.separator))
            Text("Screenshot")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            SaveScreenshotButton(model: model, screenshot: screenshot)
            IconButton(symbol: "xmark.circle.fill", help: "Remove screenshot", action: onRemove)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}

/// The workflow the chat is changing.
private struct WorkflowChip: View {
    let workflow: Workflow
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "record.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
            Text("Changing “\(workflow.name)”")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            IconButton(symbol: "xmark.circle.fill", help: "Stop changing this workflow", action: onRemove)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}

/// Saves a screenshot next to the Mac's own screenshots; once saved, a checkmark shows it in Finder.
private struct SaveScreenshotButton: View {
    let model: PromptModel
    let screenshot: Screenshot

    var body: some View {
        if let url = model.savedScreenshots[screenshot.id] {
            IconButton(symbol: "checkmark.circle.fill",
                       help: "Saved to \(url.deletingLastPathComponent().lastPathComponent). Show in Finder",
                       tint: .green) {
                model.revealSaved(screenshot)
            }
        } else {
            IconButton(symbol: "square.and.arrow.down", help: "Save screenshot to \(ScreenshotSaver.folder().lastPathComponent)") {
                Task { await model.save(screenshot) }
            }
        }
    }
}

private struct TurnView: View {
    let model: PromptModel
    let turn: PromptModel.Turn
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                if let screenshot = turn.screenshot {
                    Image(nsImage: screenshot.nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 48, maxHeight: 30, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                Text(turn.prompt)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let screenshot = turn.screenshot {
                    Spacer(minLength: 4)
                    SaveScreenshotButton(model: model, screenshot: screenshot)
                }
            }
            if let error = turn.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
            } else if turn.response.isEmpty && isStreaming {
                ProgressView()
                    .controlSize(.mini)
            } else {
                if !reply.prose.isEmpty {
                    Text(rendered)
                        .font(.system(size: 12.5))
                        .textSelection(.enabled)
                }
                if let workflow = turn.workflow, !reply.edits.isEmpty, !isStreaming {
                    WorkflowChangesView(model: model, turn: turn, workflow: workflow, edits: reply.edits)
                }
            }
        }
    }

    /// A reply about a workflow, with its changes taken out of the text.
    private var reply: (prose: String, edits: WorkflowEdits) {
        turn.workflow == nil ? (turn.response, WorkflowEdits()) : WorkflowEdits.parse(turn.response)
    }

    /// Inline markdown (bold, code, links) while keeping the model's line breaks.
    private var rendered: AttributedString {
        let text = reply.prose
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// What a reply would change in a workflow, in full, so nothing is typed that wasn't read first.
private struct WorkflowChangesView: View {
    let model: PromptModel
    let turn: PromptModel.Turn
    let workflow: Workflow
    let edits: WorkflowEdits

    var body: some View {
        let groups = WorkflowStepGroup.groups(for: workflow.steps)
        let problems = edits.problems(in: workflow.steps)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(edits.texts.keys.sorted().filter { !edits.removed.contains($0) }, id: \.self) { step in
                VStack(alignment: .leading, spacing: 2) {
                    if let problem = problems[step] {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.orange)
                    } else {
                        Text("Step \(step) now types “\(groups[step - 1].text ?? "")”")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text("It will type:")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(edits.texts[step] ?? "")
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(problems[step] == nil ? 1 : 0.5)
                }
            }
            ForEach(edits.removed.sorted(), id: \.self) { step in
                Label(problems[step] ?? "Remove step \(step): \(groups[step - 1].title)",
                      systemImage: problems[step] == nil ? "minus.circle" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(problems[step] == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Spacer()
                if !problems.isEmpty {
                    Text("Can't save: ask again, saying which step to change")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if let saved = model.savedWorkflow(for: turn) {
                    Label("Saved as “\(saved.name)”", systemImage: "checkmark")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // No keyboard shortcut: Return sends the next message, and a run types into another app.
                    Button("Run") { model.runSavedWorkflow(for: turn) }
                } else {
                    Button(workflow.editedFrom == nil ? "Save as edited copy" : "Save changes") { model.applyChanges(from: turn) }
                        .help(workflow.editedFrom == nil ? "Saves to “\(workflow.name) (edited)” and keeps the original as recorded" : "")
                }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Workflows

private struct WorkflowCard: View {
    @Bindable var model: PromptModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "record.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.sweep(angle: .degrees(0)))
                Text("Workflows")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button {
                    model.recordWorkflow()
                } label: {
                    Label("Record", systemImage: "record.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .help("Record clicks, typing and scrolling. Esc pauses; wiggle again to stop.")
            }
            .padding(.horizontal, 10)
            .padding(.top, 9)
            .padding(.bottom, 7)

            if let notice = model.notice {
                NoticeRow(notice: notice)
                    .padding(.bottom, 6)
            }

            if model.workflows.workflows.isEmpty {
                Text("Record clicks, typing and scrolling in any app, then replay them at the same spots on screen. Esc pauses recording; wiggle again to stop.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            } else {
                Divider().opacity(0.5)
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(model.workflows.workflows) { workflow in
                            WorkflowRow(workflow: workflow,
                                        onRun: { model.run(workflow) },
                                        onRename: { model.renameWorkflow(workflow, to: $0) },
                                        onChat: { model.changeWithChat(workflow) },
                                        onDelete: { model.deleteWorkflow(workflow) })
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
                Divider().opacity(0.5)
                HStack(spacing: 6) {
                    Stepper(value: $model.repeatCount, in: 1...99) {
                        Text("Run \(model.repeatCount)×")
                            .monospacedDigit()
                    }
                    .controlSize(.mini)
                    Spacer()
                    Text("esc pauses · wiggle stops")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 10.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(width: PromptPanelController.size.width - 16)
        .modifier(CardBackground(isBusy: false))
    }
}

private struct WorkflowRow: View {
    let workflow: Workflow
    let onRun: () -> Void
    let onRename: (String) -> Void
    let onChat: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var confirmingDelete = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .font(.system(size: 12, weight: .medium))
                        .focused($nameFocused)
                        .onAppear { nameFocused = true }
                        .onSubmit(finishRenaming)
                        .onExitCommand { isRenaming = false }
                } else {
                    Text(workflow.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .onTapGesture(count: 2, perform: startRenaming)
                        .help("Double-click to rename")
                }
                Text(workflow.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isRenaming {
                // Renaming: just the field and play.
            } else if confirmingDelete {
                Button("Delete", role: .destructive, action: onDelete)
                    .controlSize(.mini)
            } else if isHovered {
                IconButton(symbol: "pencil", help: "Rename workflow", action: startRenaming)
                IconButton(symbol: "text.bubble", help: "Change what it types with chat", action: onChat)
                IconButton(symbol: "trash", help: "Delete workflow") { confirmingDelete = true }
            }
            IconButton(symbol: "play.fill", help: "Run \(workflow.name)", tint: .primary) {
                finishRenaming()
                onRun()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if !hovering { confirmingDelete = false }
        }
        // Clicking away keeps the new name; Esc drops it.
        .onChange(of: nameFocused) { _, focused in
            if !focused { finishRenaming() }
        }
    }

    private func startRenaming() {
        confirmingDelete = false
        draftName = workflow.name
        isRenaming = true
    }

    private func finishRenaming() {
        guard isRenaming else { return }
        isRenaming = false
        onRename(draftName)
    }
}

private struct SaveWorkflowCard: View {
    @Bindable var model: PromptModel

    @FocusState private var focused: Bool

    var body: some View {
        let groups = WorkflowStepGroup.groups(for: model.recording)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                Text(model.recording.isEmpty ? "Nothing was recorded" : "Recorded \(Workflow.summary(of: model.recording))")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.top, 9)
            .padding(.bottom, 7)

            if model.recording.isEmpty {
                Text("No clicks, typing or scrolling in other apps were caught. Record again, and wiggle when you're done.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            } else {
                TextField("Name", text: $model.workflowName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
                    .focused($focused)
                    .onSubmit { model.saveRecording() }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                Divider().opacity(0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            HStack(spacing: 7) {
                                Image(systemName: group.symbol)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(group.title)
                                    .font(.system(size: 11.5))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 4)
                                IconButton(symbol: "xmark", help: "Remove this step") { model.removeSteps(group.range) }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 190)
                .fixedSize(horizontal: false, vertical: true)
                Divider().opacity(0.5)
            }

            HStack {
                Button("Discard", role: .destructive) { model.discardRecording() }
                Spacer()
                Button("Save") { model.saveRecording() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.recording.isEmpty)
            }
            .controlSize(.small)
            .padding(10)
        }
        .frame(width: PromptPanelController.size.width - 16)
        .modifier(CardBackground(isBusy: false))
        .onAppear { focused = true }
    }
}
