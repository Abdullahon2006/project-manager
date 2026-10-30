// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StateAndNext",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "StateAndNext",
            targets: ["StateAndNext"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "StateAndNext",
            dependencies: [],
            path: "StateAndNext"
        )
    ]
)
