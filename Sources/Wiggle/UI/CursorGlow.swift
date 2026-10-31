import AppKit
import QuartzCore

/// A click-through overlay that circles the pointer with a spinning rainbow ring while Wiggle is open.
///
/// The real pointer always stays visible: the ring only decorates it, so the pointer can't vanish
/// on any display, whatever happens to this window.
@MainActor
final class CursorGlowController {
    /// Spins faster and pulses while Wiggle is capturing or answering.
    var isThinking = false {
        didSet {
            if isThinking != oldValue { ring.setBusy(isThinking) }
        }
    }

    private let size = CGSize(width: 120, height: 120)
    private lazy var ring = RingView(frame: CGRect(origin: .zero, size: size))
    private lazy var window: NSWindow = makeWindow()
    private var tracking: Timer?
    private var isShown = false

    /// `recording` turns the ring red while a workflow is being recorded.
    func show(at point: CGPoint, recording: Bool = false) {
        isShown = true
        ring.setColors(recording ? Palette.recordingCGColors : Palette.spectrumCGColors)
        place(at: point)
        window.orderFrontRegardless()
        startTracking()
        ring.appear()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        ring.disappear { [weak self] in
            guard let self, !self.isShown else { return }
            self.stopTracking()
            self.window.orderOut(nil)
        }
    }

    /// Follows the pointer through every move and drag, whichever app is getting the mouse events.
    private func startTracking() {
        guard tracking == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.place(at: NSEvent.mouseLocation) }
        }
        RunLoop.main.add(timer, forMode: .common)
        tracking = timer
    }

    private func stopTracking() {
        tracking?.invalidate()
        tracking = nil
    }

    /// The window is centered on the pointer's tip.
    private func place(at point: CGPoint) {
        let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        guard window.frame.origin != origin else { return }
        window.setFrameOrigin(origin)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = ring
        return window
    }
}

/// The ring and its soft glow, drawn with Core Animation: the layers are vector shapes the window
/// server renders and spins on its own, so they keep drawing on any display and at any scale.
private final class RingView: NSView {
    /// The pointer's tip sits at the view's center; the ring circles the arrow just below-right of it.
    private static let ringCenter = CGPoint(x: 60 + 6, y: 60 - 10)
    private static let radius: CGFloat = 24
    private static let lineWidth: CGFloat = 3
    private static let glowRadius: CGFloat = 36
    private static let turn: TimeInterval = 2

    private let content = CALayer()
    private let pulse = CALayer()
    private let spinner = CALayer()
    private let glow = CAGradientLayer()
    private let ring = CAGradientLayer()
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build() {
        let center = Self.ringCenter
        // Scale and pulse around the ring's center.
        for container in [content, pulse] {
            container.bounds = bounds
            container.anchorPoint = CGPoint(x: center.x / bounds.width, y: center.y / bounds.height)
            container.position = center
        }
        spinner.frame = bounds
        layer?.addSublayer(content)
        content.addSublayer(pulse)
        pulse.addSublayer(spinner)

        let colors = Palette.spectrumCGColors
        let glowSide = Self.glowRadius * 2
        glow.type = .conic
        glow.colors = colors
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 0.5, y: 1)
        glow.frame = CGRect(x: center.x - Self.glowRadius, y: center.y - Self.glowRadius, width: glowSide, height: glowSide)
        glow.opacity = 0.35
        let softDisc = CAGradientLayer()
        softDisc.type = .radial
        softDisc.colors = [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)]
        softDisc.locations = [0.3, 1]
        softDisc.startPoint = CGPoint(x: 0.5, y: 0.5)
        softDisc.endPoint = CGPoint(x: 1, y: 1)
        softDisc.frame = glow.bounds
        glow.mask = softDisc
        spinner.addSublayer(glow)

        // The shadow lives on a container so it follows the masked ring, not the square gradient.
        let ringShadow = CALayer()
        ringShadow.frame = bounds
        ringShadow.shadowColor = CGColor(gray: 0, alpha: 1)
        ringShadow.shadowOpacity = 0.35
        ringShadow.shadowRadius = 2
        ringShadow.shadowOffset = CGSize(width: 0, height: -1)
        spinner.addSublayer(ringShadow)

        let ringSide = (Self.radius + Self.lineWidth) * 2
        ring.type = .conic
        ring.colors = colors
        ring.startPoint = CGPoint(x: 0.5, y: 0.5)
        ring.endPoint = CGPoint(x: 0.5, y: 1)
        ring.frame = CGRect(x: center.x - ringSide / 2, y: center.y - ringSide / 2, width: ringSide, height: ringSide)
        let band = CAShapeLayer()
        band.frame = ring.bounds
        let r = Self.radius - Self.lineWidth / 2
        band.path = CGPath(ellipseIn: CGRect(x: ringSide / 2 - r, y: ringSide / 2 - r, width: r * 2, height: r * 2), transform: nil)
        band.fillColor = nil
        band.strokeColor = CGColor(gray: 0, alpha: 1)
        band.lineWidth = Self.lineWidth
        ring.mask = band
        ringShadow.addSublayer(ring)

        if !reduceMotion {
            for layer in [glow, ring] {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = -2 * Double.pi
                spin.duration = Self.turn
                spin.repeatCount = .infinity
                spin.isRemovedOnCompletion = false
                layer.add(spin, forKey: "spin")
            }
        }
        withoutAnimation {
            content.opacity = 0
            content.transform = CATransform3DMakeScale(0.3, 0.3, 1)
        }
        updateScale()
    }

    func appear() {
        content.removeAllAnimations()
        withoutAnimation {
            content.opacity = 1
            content.transform = CATransform3DIdentity
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.15
        content.add(fade, forKey: "fade")
        guard !reduceMotion else { return }
        // The same spring the panel uses for its cursor: response 0.35 s, damping fraction 0.6.
        let grow = CASpringAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1
        grow.mass = 1
        grow.stiffness = 322
        grow.damping = 21.5
        grow.duration = grow.settlingDuration
        content.add(grow, forKey: "grow")
    }

    func disappear(completion: @escaping @MainActor () -> Void) {
        let shown = content.presentation()
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = shown?.opacity ?? 1
        fade.toValue = 0
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = shown?.value(forKeyPath: "transform.scale") ?? 1
        shrink.toValue = 0.3
        for animation in [fade, shrink] {
            animation.duration = 0.2
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        }
        content.removeAllAnimations()
        withoutAnimation {
            content.opacity = 0
            content.transform = CATransform3DMakeScale(0.3, 0.3, 1)
        }
        content.add(fade, forKey: "fade")
        content.add(shrink, forKey: "shrink")
        CATransaction.commit()
    }

    func setColors(_ colors: [CGColor]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.colors = colors
        ring.colors = colors
        CATransaction.commit()
    }

    /// Busy: the rainbow turns three times as fast and the ring breathes.
    func setBusy(_ busy: Bool) {
        guard !reduceMotion else { return }
        // Change the speed without a jump: keep the spinner's local time continuous.
        let now = CACurrentMediaTime()
        let local = spinner.convertTime(now, from: nil)
        spinner.speed = busy ? 3 : 1
        spinner.timeOffset = local
        spinner.beginTime = pulse.convertTime(now, from: nil)

        if busy {
            let breathe = CABasicAnimation(keyPath: "transform.scale")
            breathe.fromValue = 1
            breathe.toValue = 1.12
            breathe.duration = 0.52
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.add(breathe, forKey: "breathe")
        } else {
            pulse.removeAnimation(forKey: "breathe")
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    /// Layer-hosting views don't get their scale updated by AppKit; keep the shapes sharp on every display.
    private func updateScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        var stack: [CALayer] = layer.map { [$0] } ?? []
        while let next = stack.popLast() {
            next.contentsScale = scale
            stack.append(contentsOf: next.sublayers ?? [])
            if let mask = next.mask { stack.append(mask) }
        }
    }

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
