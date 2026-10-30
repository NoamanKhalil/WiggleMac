// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Wiggle",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "Wiggle",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Wiggle"
        ),
        .testTarget(
            name: "WiggleTests",
            dependencies: ["Wiggle"],
            path: "Tests/WiggleTests"
        ),
    ]
)
