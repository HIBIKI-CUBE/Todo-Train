// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TodoTrainSync",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TodoTrainSync", targets: ["TodoTrainSync"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.10.0"),
    ],
    targets: [
        .target(
            name: "TodoTrainSync",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "TodoTrainSyncTests",
            dependencies: ["TodoTrainSync"]
        ),
    ]
)
