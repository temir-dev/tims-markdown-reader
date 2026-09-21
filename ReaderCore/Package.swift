// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ReaderCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-markdown.git",
            exact: "0.8.0"
        ),
    ],
    targets: [
        .target(
            name: "ReaderCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "ReaderCoreTests",
            dependencies: ["ReaderCore"]
        ),
    ]
)
