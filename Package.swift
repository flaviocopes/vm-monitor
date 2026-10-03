// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "VMMonitor",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "MonitorCore", targets: ["MonitorCore"]),
    .executable(name: "VMMonitorApp", targets: ["VMMonitorApp"])
  ],
  targets: [
    .target(name: "MonitorCore"),
    .executableTarget(
      name: "VMMonitorApp",
      dependencies: ["MonitorCore"]
    ),
    .testTarget(
      name: "MonitorCoreTests",
      dependencies: ["MonitorCore"]
    )
  ]
)
