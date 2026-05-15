// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeMonitor",
            path: "Sources/ClaudeMonitor",
            resources: [
                .copy("Resources/claude.svg"),
                .copy("Resources/codex.svg"),
                .copy("Resources/AppIcon.icns"),
            ]
        )
    ]
)
