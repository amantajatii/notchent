// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "NativeIsland", platforms: [.macOS(.v14)], products: [.library(name: "IslandCore", targets: ["IslandCore"]), .executable(name: "IslandProbe", targets: ["IslandProbe"]), .executable(name: "IslandMac", targets: ["IslandMac"])], targets: [.target(name: "IslandCore"), .executableTarget(name: "IslandProbe", dependencies: ["IslandCore"]), .executableTarget(name: "IslandMac", dependencies: ["IslandCore"], exclude: ["Resources"]), .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"])])
