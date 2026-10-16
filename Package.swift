// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PauseGuard",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PauseGuardCore", targets: ["PauseGuardCore"]),
               .library(name: "PauseGuardPlatform", targets: ["PauseGuardPlatform"])],
    targets: [
        .target(name: "PauseGuardCore"),
        .target(name: "PauseGuardPlatform", dependencies: ["PauseGuardCore"]),
        .testTarget(name: "PauseGuardPlatformTests", dependencies: ["PauseGuardPlatform"]),
        .testTarget(name: "PauseGuardCoreTests", dependencies: ["PauseGuardCore"])
    ]
)
