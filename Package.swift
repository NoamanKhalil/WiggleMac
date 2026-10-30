// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Wiggle",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Wiggle",
            path: "Sources/Wiggle"
        ),
        .testTarget(
            name: "WiggleTests",
            dependencies: ["Wiggle"],
            path: "Tests/WiggleTests"
        ),
    ]
)
