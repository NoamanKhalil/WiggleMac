import SwiftUI

enum Palette {
    private static let stops: [(red: Double, green: Double, blue: Double)] = [
        (0.26, 0.52, 0.96),  // blue
        (0.58, 0.42, 0.86),  // violet
        (0.89, 0.38, 0.58),  // pink
        (0.93, 0.30, 0.24),  // red
        (0.98, 0.74, 0.10),  // yellow
        (0.22, 0.70, 0.40),  // green
        (0.26, 0.52, 0.96),  // back to blue to close the loop
    ]

    /// Multicolor sweep used for the ring around the pointer and the panel border.
    static let spectrum: [Color] = stops.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }

    /// The same sweep for Core Animation layers.
    @MainActor static let spectrumCGColors: [CGColor] = stops.map {
        CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
    }

    static func sweep(angle: Angle) -> AngularGradient {
        AngularGradient(colors: spectrum, center: .center, angle: angle)
    }
}
