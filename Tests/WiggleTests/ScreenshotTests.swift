import AppKit
import Foundation
import Testing
@testable import Wiggle

struct ScreenshotTests {
    private func solidImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        context.setFillColor(CGColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test func sendsAScaledCopyButKeepsTheOriginal() {
        let screenshot = Screenshot(original: solidImage(width: 3024, height: 1964), scale: 2)
        #expect(screenshot.original.width == 3024)
        #expect(screenshot.image.width == Int(Screenshot.maxEdge))
        #expect(screenshot.image.height == 1018)
        #expect(!screenshot.jpeg.isEmpty)
    }

    @Test func leavesSmallCapturesAlone() {
        let screenshot = Screenshot(original: solidImage(width: 900, height: 300))
        #expect(screenshot.image.width == 900)
        #expect(screenshot.image.height == 300)
    }

    @Test func savesTheFullResolutionPNG() throws {
        let screenshot = Screenshot(original: solidImage(width: 3024, height: 1964), scale: 2)
        let rep = try #require(screenshot.pngData().flatMap(NSBitmapImageRep.init(data:)))
        #expect(rep.pixelsWide == 3024)
        #expect(rep.pixelsHigh == 1964)
        // Opens at the display's point size, like a macOS screenshot.
        #expect(rep.size == NSSize(width: 1512, height: 982))
    }
}

struct ScreenshotSaverTests {
    private let folder = URL(fileURLWithPath: "/tmp/screens", isDirectory: true)
    private let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 20, minute: 41, second: 12))!

    @Test func namesFilesLikeMacOS() {
        let url = ScreenshotSaver.destination(in: folder, at: date, exists: { _ in false })
        #expect(url.lastPathComponent == "Wiggle Screenshot 2026-10-05 at 20.41.12.png")
        #expect(url.deletingLastPathComponent().path == "/tmp/screens")
    }

    @Test func numbersNamesThatAreTaken() {
        let taken: Set<String> = ["Wiggle Screenshot 2026-10-05 at 20.41.12.png", "Wiggle Screenshot 2026-10-05 at 20.41.12 (2).png"]
        let url = ScreenshotSaver.destination(in: folder, at: date, exists: { taken.contains($0.lastPathComponent) })
        #expect(url.lastPathComponent == "Wiggle Screenshot 2026-10-05 at 20.41.12 (3).png")
    }

    @Test func usesTheMacsScreenshotFolder() {
        let custom = FileManager.default.temporaryDirectory.path
        #expect(ScreenshotSaver.folder(configured: custom).path == URL(fileURLWithPath: custom).path)
        #expect(ScreenshotSaver.folder(configured: "~").path == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @Test func fallsBackToTheDesktop() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        #expect(ScreenshotSaver.folder(configured: nil) == desktop)
        #expect(ScreenshotSaver.folder(configured: "/no/such/folder") == desktop)
    }
}
