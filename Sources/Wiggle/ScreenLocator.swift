import AppKit

/// Finds the display under a point in AppKit's global screen coordinates.
enum ScreenLocator {
    /// The frame under `point`. Unlike `CGRect.contains`, the top and right edges count as inside,
    /// since the pointer can rest there (at the top of a display its y equals `maxY`). A point that's
    /// off every display gets the nearest one.
    static func index(of point: CGPoint, in frames: [CGRect]) -> Int? {
        if let inside = frames.firstIndex(where: {
            point.x >= $0.minX && point.x <= $0.maxX && point.y >= $0.minY && point.y <= $0.maxY
        }) {
            return inside
        }
        return frames.indices.min { distance(from: point, to: frames[$0]) < distance(from: point, to: frames[$1]) }
    }

    @MainActor
    static func screen(containing point: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return index(of: point, in: screens.map(\.frame)).map { screens[$0] } ?? NSScreen.main
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
