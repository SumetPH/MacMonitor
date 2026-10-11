// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "MacMonitor",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "MacMonitor", targets: ["MacMonitor"]),
  ],
  targets: [
    .target(name: "MacMonitorCore"),
    .executableTarget(
      name: "MacMonitor",
      dependencies: ["MacMonitorCore"]
    ),
    .testTarget(
      name: "MacMonitorCoreTests",
      dependencies: ["MacMonitorCore"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
