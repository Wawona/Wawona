// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Wawona",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "WawonaUI", type: .dynamic, targets: ["WawonaUI"]),
        .library(name: "WawonaModel", type: .dynamic, targets: ["WawonaModel"]),
        .library(name: "WawonaUIContracts", type: .dynamic, targets: ["WawonaUIContracts"]),
        .library(name: "WawonaWatch", type: .dynamic, targets: ["WawonaWatch"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WawonaUIContracts",
            dependencies: []
        ),
        .target(
            name: "WawonaModel",
            dependencies: [
                "WawonaUIContracts"
            ]
        ),
        .target(
            name: "WawonaUI",
            dependencies: [
                "WawonaModel",
                "WawonaUIContracts"
            ]
        ),
        .target(
            name: "WawonaWatch",
            dependencies: [
                "WawonaModel",
                "WawonaUI"
            ]
        ),
        .testTarget(
            name: "WawonaUIContractsTests",
            dependencies: [
                "WawonaUIContracts"
            ]
        ),
        .testTarget(
            name: "WawonaModelSettingsTests",
            dependencies: [
                "WawonaModel"
            ]
        )
    ]
)
