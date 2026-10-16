// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PauseGuard",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PauseGuardCore", targets: ["PauseGuardCore"])],
    targets: [
        .target(name: "PauseGuardCore"),
        .testTarget(name: "PauseGuardCoreTests", dependencies: ["PauseGuardCore"])
    ]
)
