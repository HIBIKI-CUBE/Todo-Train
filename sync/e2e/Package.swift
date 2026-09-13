// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TodoTrainSyncE2E",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../../Packages/TodoTrainSync"),
    ],
    targets: [
        .testTarget(
            name: "TodoTrainSyncE2ETests",
            dependencies: [
                .product(name: "TodoTrainSync", package: "TodoTrainSync"),
            ]
        ),
    ]
)
