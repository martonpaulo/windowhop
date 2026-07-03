// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WindowHop",
    platforms: [.macOS(.v14)],
    dependencies: [
        // the one approved runtime dependency: automatic updates
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "WindowHopCore",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/WindowHopCore"
        ),
        .executableTarget(
            name: "WindowHop",
            dependencies: [
                "WindowHopCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/WindowHop",
            linkerSettings: [
                // the app bundle embeds Sparkle.framework in Contents/Frameworks
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "WindowHopTests",
            dependencies: ["WindowHopCore"],
            path: "Tests/WindowHopTests"
        ),
    ]
)
