// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "DayfoldCore",
    products: [.library(name: "DayfoldCore", targets: ["DayfoldCore"])],
    targets: [
        .target(name: "DayfoldCore", path: "Shared", sources: ["DayfoldModels.swift"]),
        .testTarget(name: "DayfoldCoreTests", dependencies: ["DayfoldCore"], path: "Tests")
    ]
)
