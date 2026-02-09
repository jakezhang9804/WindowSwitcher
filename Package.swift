// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WindowSwitcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WindowSwitcher", targets: ["WindowSwitcher"])
    ],
    dependencies: [
        .package(path: "Libraries/AppSwitcherKit"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "WindowSwitcher",
            dependencies: [
                "AppSwitcherKit",
                "KeyboardShortcuts",
                "Sparkle"
            ],
            path: "WindowSwitcher/Sources"
        )
    ]
)
