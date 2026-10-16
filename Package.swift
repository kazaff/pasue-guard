// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PauseGuard",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PauseGuardImages", targets: ["PauseGuardImages"]),
               .library(name: "PauseGuardCore", targets: ["PauseGuardCore"]),
               .library(name: "PauseGuardPlatform", targets: ["PauseGuardPlatform"]),
               .library(name: "PauseGuardApp", targets: ["PauseGuardApp"])],
    targets: [
        .target(name: "PauseGuardImages"),
        .testTarget(name: "PauseGuardImagesTests", dependencies: ["PauseGuardImages"]),
        .target(name: "PauseGuardCore"),
        .target(name: "PauseGuardPlatform", dependencies: ["PauseGuardCore"]),
        .target(name: "PauseGuardApp", dependencies: ["PauseGuardCore", "PauseGuardPlatform"]),
        .testTarget(name: "PauseGuardAppTests", dependencies: ["PauseGuardApp"]),
        .testTarget(name: "PauseGuardPlatformTests", dependencies: ["PauseGuardPlatform"]),
        .testTarget(name: "PauseGuardCoreTests", dependencies: ["PauseGuardCore"])
    ]
)
