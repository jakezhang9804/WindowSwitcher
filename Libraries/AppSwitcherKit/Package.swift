// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppSwitcherKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AppSwitcherKit",
            targets: ["AppSwitcherKit"]
        )
    ],
    targets: [
        .target(
            name: "AppSwitcherKit"
        ),
        .testTarget(
            name: "AppSwitcherKitTests",
            dependencies: ["AppSwitcherKit"]
        )
    ]
)
