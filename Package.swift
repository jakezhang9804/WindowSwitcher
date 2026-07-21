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
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(path: "Libraries/AppSwitcherKit")
    ],
    targets: [
        .executableTarget(
            name: "WindowSwitcher",
            dependencies: [
                "KeyboardShortcuts",
                "AppSwitcherKit"
            ],
            path: "WindowSwitcher/Sources"
        )
    ]
)
