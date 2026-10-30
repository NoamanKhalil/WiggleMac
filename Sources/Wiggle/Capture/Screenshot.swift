import AppKit
import ScreenCaptureKit
import Vision

/// A full-screen capture: the original for saving, and a scaled-down copy for sending to a model.
struct Screenshot: Identifiable, @unchecked Sendable {
    /// Longest edge sent to models. Claude, OpenAI and the local vision models all work well at this size.
    static let maxEdge: CGFloat = 1568

    let id = UUID()
    /// Full resolution, as captured. Only used when saving.
    let original: CGImage
    /// Pixels per point of the captured display, so a saved file opens at the same size as a macOS screenshot.
    let scale: CGFloat
    /// Scaled to fit `maxEdge`. This is what models, OCR and thumbnails use.
    let image: CGImage
    let jpeg: Data

    var base64JPEG: String { jpeg.base64EncodedString() }
    var nsImage: NSImage { NSImage(cgImage: image, size: .zero) }

    init(original: CGImage, scale: CGFloat = 1) {
        self.original = original
        self.scale = scale
        self.image = original.scaledToFit(Self.maxEdge) ?? original
        let rep = NSBitmapImageRep(cgImage: image)
        self.jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) ?? Data()
    }

    /// The full-resolution capture as a PNG.
    func pngData() -> Data? {
        let rep = NSBitmapImageRep(cgImage: original)
        rep.size = NSSize(width: CGFloat(original.width) / scale, height: CGFloat(original.height) / scale)
        return rep.representation(using: .png, properties: [:])
    }

    /// On-device OCR, for models that can't take images.
    func recognizedText() async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        guard let observations = try? await request.perform(on: image) else { return "" }
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

enum ScreenCapture {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case noDisplay

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Wiggle needs Screen Recording permission to take screenshots. Allow it in System Settings, then try again."
            case .noDisplay:
                "Couldn't find the screen to capture."
            }
        }
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// Captures the whole display that contains `point` (in AppKit screen coordinates) at full resolution,
    /// leaving out Wiggle's own windows and the pointer.
    @MainActor
    static func captureScreen(containing point: CGPoint) async throws -> Screenshot {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }

        let screen = ScreenLocator.screen(containing: point)
        guard let screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { throw CaptureError.noDisplay }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let wiggle = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: wiggle, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
        config.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Screenshot(original: image, scale: screen.backingScaleFactor)
    }
}

private extension CGImage {
    /// A copy whose longer edge is `maxEdge` pixels, or nil when it already fits.
    func scaledToFit(_ maxEdge: CGFloat) -> CGImage? {
        let factor = maxEdge / CGFloat(max(width, height))
        guard factor < 1 else { return nil }
        let size = CGSize(width: (CGFloat(width) * factor).rounded(), height: (CGFloat(height) * factor).rounded())
        // Keep the display's color space when a bitmap context supports it, else fall back to sRGB.
        for space in [colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap({ $0 }) {
            guard let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { continue }
            context.interpolationQuality = .high
            context.draw(self, in: CGRect(origin: .zero, size: size))
            return context.makeImage()
        }
        return nil
    }
}
