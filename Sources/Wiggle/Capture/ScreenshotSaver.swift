import Foundation

/// Saves screenshots where macOS saves its own: the Desktop, unless changed in the Screenshot app.
enum ScreenshotSaver {
    enum SaveError: LocalizedError {
        case encodingFailed

        var errorDescription: String? { "The screenshot couldn't be converted to PNG." }
    }

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!

    /// Writes the full-resolution PNG and returns where it went. Runs off the main thread,
    /// since a Files & Folders permission prompt holds up the write until it's answered.
    static func save(_ screenshot: Screenshot) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard let png = screenshot.pngData() else { throw SaveError.encodingFailed }
            let url = destination(in: folder())
            try png.write(to: url, options: .withoutOverwriting)
            return url
        }.value
    }

    /// The folder macOS saves screenshots to (`com.apple.screencapture location`) if it exists, else the Desktop.
    static func folder(
        configured: String? = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
    ) -> URL {
        if let configured, !configured.isEmpty {
            let path = (configured as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// "Wiggle Screenshot 2026-10-05 at 20.41.12.png", numbered if that name is taken.
    static func destination(
        in folder: URL,
        at date: Date = .now,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Wiggle Screenshot \(formatter.string(from: date))"
        var url = folder.appendingPathComponent("\(name).png")
        var copy = 2
        while exists(url) {
            url = folder.appendingPathComponent("\(name) (\(copy)).png")
            copy += 1
        }
        return url
    }
}
