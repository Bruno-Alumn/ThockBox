// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Thockbox",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Thockbox",
            path: "Sources/Thockbox"
        ),
        .testTarget(
            name: "ThockboxTests",
            dependencies: ["Thockbox"],
            path: "Tests/ThockboxTests"
        ),
    ]
)
