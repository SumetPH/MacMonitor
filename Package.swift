// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacMonitor",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MacMonitor"
        ),
        .testTarget(
            name: "MacMonitorTests",
            dependencies: ["MacMonitor"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
