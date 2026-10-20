// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TodoTrainTicketUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TodoTrainTicketUI", targets: ["TodoTrainTicketUI"]),
    ],
    targets: [
        .target(name: "TodoTrainTicketUI"),
    ]
)
