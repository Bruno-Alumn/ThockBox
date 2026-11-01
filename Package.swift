// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpenKlack",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OpenKlack",
            path: "Sources/OpenKlack"
        ),
        .testTarget(
            name: "OpenKlackTests",
            dependencies: ["OpenKlack"],
            path: "Tests/OpenKlackTests"
        ),
    ]
)
