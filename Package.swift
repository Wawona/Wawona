// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Wawona",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "WawonaUI", type: .dynamic, targets: ["WawonaUI"]),
        .library(name: "WawonaModel", type: .dynamic, targets: ["WawonaModel"]),
        .library(name: "WawonaUIContracts", type: .dynamic, targets: ["WawonaUIContracts"]),
        .library(name: "WawonaWatch", type: .dynamic, targets: ["WawonaWatch"])
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.8.6"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.14.3"),
        .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.2"),
        .package(url: "https://source.skip.tools/skip-model.git", from: "1.7.2")
    ],
    targets: [
        .target(
            name: "WawonaUIContracts",
            dependencies: [
                .product(name: "SkipModel", package: "skip-model")
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "WawonaModel",
            dependencies: [
                "WawonaUIContracts",
                .product(name: "SkipFuse", package: "skip-fuse"),
                .product(name: "SkipModel", package: "skip-model")
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "WawonaUI",
            dependencies: [
                "WawonaModel",
                "WawonaUIContracts",
                .product(name: "SkipFuseUI", package: "skip-fuse-ui")
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "WawonaWatch",
            dependencies: [
                "WawonaModel",
                "WawonaUI",
                .product(name: "SkipFuse", package: "skip-fuse")
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
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
