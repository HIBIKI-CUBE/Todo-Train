// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TodoTrainQRUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TodoTrainQRUI", targets: ["TodoTrainQRUI"]),
    ],
    targets: [
        .target(name: "TodoTrainQRUI"),
        .testTarget(
            name: "TodoTrainQRUITests",
            dependencies: ["TodoTrainQRUI"]
        ),
    ]
)
