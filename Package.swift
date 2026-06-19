// swift-tools-version: 5.9
// GitSync - macOS 菜单栏 Git 同步工具

import PackageDescription

let package = Package(
    name: "GitSync",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "GitSync",
            path: "Sources/GitSync"
        ),
    ]
)
