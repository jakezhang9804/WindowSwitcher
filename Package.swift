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
        .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", from: "2.6.0"),
        .package(path: "Libraries/AppSwitcherKit")
    ],
    targets: [
        .executableTarget(
            name: "WindowSwitcher",
            dependencies: [
                "KeyboardShortcuts",
                "AppSwitcherKit",
                .product(name: "PermissionFlow", package: "PermissionFlow"),
                .product(name: "PermissionFlowScreenRecordingStatus", package: "PermissionFlow")
            ],
            path: "WindowSwitcher/Sources"
        )
    ]
)
