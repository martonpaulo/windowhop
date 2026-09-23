// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    // any compiler warning fails the build, locally and in CI (SE-0480; remote packages are exempt)
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "WindowHop",
    platforms: [.macOS(.v26)],
    dependencies: [
        // the one approved runtime dependency: automatic updates
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(
            name: "WindowHopCore",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/WindowHopCore",
            swiftSettings: swiftSettings,
        ),
        .executableTarget(
            name: "WindowHop",
            dependencies: [
                "WindowHopCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/WindowHop",
            swiftSettings: swiftSettings,
            linkerSettings: [
                // the app bundle embeds Sparkle.framework in Contents/Frameworks
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "WindowHopTests",
            dependencies: ["WindowHopCore"],
            path: "Tests/WindowHopTests",
            // AeroSpace's MIT-licensed AX dump corpus, imported verbatim (UPSTREAM.md)
            resources: [.copy("Fixtures/AeroSpaceAXDumps")],
            swiftSettings: swiftSettings,
        ),
    ]
)
