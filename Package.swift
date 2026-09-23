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
        // pure rules: Foundation, CoreGraphics value types, Observation and
        // Synchronization only (AGENTS.md "Kit import contract"; scripts/validate.sh)
        .target(
            name: "WindowHopKit",
            path: "Sources/WindowHopKit",
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "WindowHopCore",
            dependencies: [
                "WindowHopKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/WindowHopCore",
            swiftSettings: swiftSettings,
        ),
        .executableTarget(
            name: "WindowHop",
            dependencies: [
                "WindowHopKit",
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
        // test-only: the one place a test makes a UserDefaults suite (#129)
        .target(
            name: "WindowHopTestSupport",
            path: "Tests/WindowHopTestSupport",
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "WindowHopKitTests",
            dependencies: ["WindowHopKit", "WindowHopTestSupport"],
            path: "Tests/WindowHopKitTests",
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "WindowHopTests",
            dependencies: ["WindowHopKit", "WindowHopCore", "WindowHopTestSupport"],
            path: "Tests/WindowHopTests",
            // AeroSpace's MIT-licensed AX dump corpus, imported verbatim (UPSTREAM.md)
            resources: [.copy("Fixtures/AeroSpaceAXDumps")],
            swiftSettings: swiftSettings,
        ),
    ]
)
