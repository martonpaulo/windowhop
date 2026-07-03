// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WindowHop",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "WindowHopCore",
            path: "Sources/WindowHopCore"
        ),
        .executableTarget(
            name: "WindowHop",
            dependencies: ["WindowHopCore"],
            path: "Sources/WindowHop"
        ),
        .testTarget(
            name: "WindowHopTests",
            dependencies: ["WindowHopCore"],
            path: "Tests/WindowHopTests"
        ),
    ]
)
