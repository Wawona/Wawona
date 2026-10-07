// swift-tools-version: 6.1
import PackageDescription

/// Slim package for Verification Swift differential (SSH host vector).
/// Sources/Tests are symlinks into the repo Sources/WawonaUIContracts trees.
/// Root Package.swift also builds WawonaUI, which needs WawonaApple (not SPM).
let package = Package(
    name: "WawonaSSHVector",
    platforms: [
        .macOS(.v14),
        .iOS(.v13),
    ],
    products: [
        .library(name: "WawonaUIContracts", targets: ["WawonaUIContracts"]),
    ],
    targets: [
        .target(name: "WawonaUIContracts"),
        .testTarget(
            name: "WawonaUIContractsTests",
            dependencies: ["WawonaUIContracts"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
