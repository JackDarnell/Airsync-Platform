// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirSync",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "AirSync",
            targets: ["AirSync"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AirSync",
            dependencies: []
        ),
        .testTarget(
            name: "AirSyncTests",
            dependencies: ["AirSync"]
        ),
    ]
)
