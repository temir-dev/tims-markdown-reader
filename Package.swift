// swift-tools-version: 6.0
import PackageDescription

// Native integration-test harness; the shipping app is still built by Xcode.
let package = Package(
    name: "MarkdownReaderVerification",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "ReaderCore")],
    targets: [
        .target(
            name: "ReaderApp",
            dependencies: [.product(name: "ReaderCore", package: "ReaderCore")],
            path: "MarkdownReader",
            exclude: ["Assets.xcassets", "Info.plist"]
        ),
        .testTarget(name: "ReaderAppTests", dependencies: ["ReaderApp", .product(name: "ReaderCore", package: "ReaderCore")], path: "Tests/ReaderAppTests")
    ],
    swiftLanguageModes: [.v5]
)
