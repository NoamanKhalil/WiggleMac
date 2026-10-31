import AppKit
import SwiftUI

/// A small floating bar while a workflow runs or records: what's going on, and buttons to pause, resume
/// and stop it. It never takes focus, so the app the workflow is working in stays in front.
@MainActor
final class WorkflowControlsController {
    static let size = CGSize(width: 320, height: 62)

    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false  // Wiggle is never the active app while a workflow runs
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    func show(_ player: WorkflowPlayer, running workflow: Workflow) {
        // Workflow points are in global display space, where y runs down from the top of the main display.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let points = workflow.steps.flatMap(\.action.points).map { CGPoint(x: $0.x, y: top - $0.y) }
        show(PlayerControls(player: player), avoiding: points)
    }

    func show(_ recorder: WorkflowRecorder, onStop: @escaping () -> Void) {
        show(RecorderControls(recorder: recorder, onStop: onStop), avoiding: [])
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func show(_ controls: some View, avoiding points: [CGPoint]) {
        let screen = ScreenLocator.screen(containing: NSEvent.mouseLocation)
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: Self.size)
        panel.contentView = FirstClickHostingView(rootView: controls)
        panel.setFrame(Self.frame(size: Self.size, in: visible, avoiding: points), display: false)
        panel.orderFrontRegardless()
    }

    /// Bottom center, unless the workflow clicks, drags or scrolls there: replayed input landing on the
    /// bar would press its buttons instead. Then the first spot along the screen's edges with the fewest.
    nonisolated static func frame(size: CGSize, in visible: CGRect, avoiding points: [CGPoint]) -> CGRect {
        let inset: CGFloat = 12
        let center = visible.midX - size.width / 2
        let left = visible.minX + inset, right = visible.maxX - inset - size.width
        let bottom = visible.minY + inset, top = visible.maxY - inset - size.height
        let spots = [
            CGPoint(x: center, y: bottom), CGPoint(x: center, y: top),
            CGPoint(x: right, y: bottom), CGPoint(x: left, y: bottom),
            CGPoint(x: right, y: top), CGPoint(x: left, y: top),
        ].map { CGRect(origin: $0, size: size) }

        func hits(_ spot: CGRect) -> Int {
            let zone = spot.insetBy(dx: -16, dy: -16)
            return points.count(where: zone.contains)
        }
        // `min(by:)` keeps the first of equally good spots.
        return spots.min { hits($0) < hits($1) } ?? spots[0]
    }
}

/// Wiggle isn't the active app while a workflow runs: take the first click anyway, so one click
/// presses a button.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct PlayerControls: View {
    let player: WorkflowPlayer

    var body: some View {
        ControlBar(symbol: "play.circle.fill", tint: AnyShapeStyle(Palette.sweep(angle: .degrees(0))),
                   title: player.workflow?.name ?? "", detail: progress, isPaused: player.isPaused,
                   stopHelp: "Stop (or wiggle)", onTogglePause: player.togglePause, onStop: player.stop)
    }

    /// "Step 3 of 14 · run 2 of 5"
    private var progress: String {
        var text = "\(player.isPaused ? "Paused · step" : "Step") \(player.step + 1) of \(player.workflow?.steps.count ?? 0)"
        if player.runs > 1 { text += " · run \(player.run + 1) of \(player.runs)" }
        return text
    }
}

private struct RecorderControls: View {
    let recorder: WorkflowRecorder
    let onStop: () -> Void

    var body: some View {
        ControlBar(symbol: "record.circle.fill", tint: AnyShapeStyle(.red), title: "Recording", detail: detail,
                   isPaused: recorder.isPaused, stopHelp: "Stop and review (or wiggle)",
                   onTogglePause: recorder.togglePause, onStop: onStop)
    }

    /// "Paused · 4 steps"
    private var detail: String {
        let count = recorder.stepCount
        let steps = count == 0 ? "no steps yet" : count == 1 ? "1 step" : "\(count) steps"
        return recorder.isPaused ? "Paused · \(steps)" : steps.prefix(1).uppercased() + steps.dropFirst()
    }
}

private struct ControlBar: View {
    let symbol: String
    let tint: AnyShapeStyle
    let title: String
    let detail: String
    let isPaused: Bool
    let stopHelp: String
    let onTogglePause: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isPaused ? "pause.circle.fill" : symbol)
                .font(.system(size: 18))
                .foregroundStyle(isPaused ? AnyShapeStyle(.orange) : tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            ControlButton(symbol: isPaused ? "play.fill" : "pause.fill",
                          help: isPaused ? "Resume (esc)" : "Pause (esc)", action: onTogglePause)
            ControlButton(symbol: "stop.fill", help: stopHelp, action: onStop)
        }
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .frame(width: WorkflowControlsController.size.width - 16, height: WorkflowControlsController.size.height - 16)
        .modifier(CardBackground(isBusy: !isPaused))
    }
}

private struct ControlButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.14 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
