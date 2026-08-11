// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LocalSub",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LocalSubCore", targets: ["LocalSubCore"]),
        .library(name: "LocalSubApple", targets: ["LocalSubApple"]),
        .library(name: "LocalSubCloud", targets: ["LocalSubCloud"]),
        .executable(name: "localsub", targets: ["LocalSubCLI"]),
        .executable(name: "LocalSubApp", targets: ["LocalSubApp"]),
    ],
    targets: [
        .target(name: "LocalSubCore"),
        .target(name: "LocalSubApple", dependencies: ["LocalSubCore"]),
        .target(name: "LocalSubCloud", dependencies: ["LocalSubCore"]),
        .executableTarget(name: "LocalSubCLI", dependencies: ["LocalSubCore", "LocalSubApple", "LocalSubCloud"]),
        .executableTarget(name: "LocalSubApp", dependencies: ["LocalSubCore", "LocalSubApple", "LocalSubCloud"]),
        .testTarget(name: "LocalSubCoreTests", dependencies: ["LocalSubCore"]),
        .testTarget(name: "LocalSubAppleIntegrationTests", dependencies: ["LocalSubApple"]),
        .testTarget(name: "LocalSubCloudTests", dependencies: ["LocalSubCloud"]),
    ]
)
