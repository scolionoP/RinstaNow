// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "IGDMClient",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "IGDMClient", targets: ["IGDMClient"])
    ],
    targets: [
        .executableTarget(
            name: "IGDMClient"
        )
    ]
)
