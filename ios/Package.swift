// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProjectManager",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ProjectManager",
            targets: ["ProjectManager"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ProjectManager",
            dependencies: [],
            path: "ProjectManager"
        )
    ]
)
