// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ScoreForge",
    platforms: [
        .iOS(.v17), .macOS(.v13)
    ],
    products: [
        // The cross-platform core engine. Contains no UI; safe to reuse as an
        // OSS component (see docs/design.md §6.3 "コアの部品化").
        .library(name: "ScoreForgeKit", targets: ["ScoreForgeKit"]),
        // The SwiftUI renderer (docs/design.md §10.2). Builds only on Apple
        // platforms — every file is guarded by `#if canImport(SwiftUI)`, so on
        // Linux it compiles to an empty module and the core stays testable.
        .library(name: "ScoreForgeUI", targets: ["ScoreForgeUI"]),
        // A tiny command-line driver used to exercise the engine without iOS.
        .executable(name: "scoreforge-cli", targets: ["scoreforge-cli"]),
    ],
    targets: [
        .target(
            name: "ScoreForgeKit",
            resources: [.process("Presets/Resources")]
        ),
        .target(
            name: "ScoreForgeUI",
            dependencies: ["ScoreForgeKit"]
        ),
        .executableTarget(
            name: "scoreforge-cli",
            dependencies: ["ScoreForgeKit"],
            path: "Tools/scoreforge-cli"
        ),
        .testTarget(
            name: "ScoreForgeKitTests",
            dependencies: ["ScoreForgeKit"]
        ),
    ]
)
