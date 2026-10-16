// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenLayout",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "ScreenLayout", targets: ["ScreenLayout"])],
    targets: [
        .target(name: "SpaceBridge", publicHeadersPath: "include"),
        .executableTarget(name: "ScreenLayout", dependencies: ["SpaceBridge"])
    ]
)
