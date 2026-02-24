// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KTApple",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KTAppleCore", targets: ["KTAppleCore"]),
    ],
    targets: [
        .executableTarget(
            name: "KTApple",
            dependencies: ["KTAppleCore"]
        ),
        .target(
            name: "KTAppleCore"
        ),
        .testTarget(
            name: "KTAppleCoreTests",
            dependencies: ["KTAppleCore"]
        ),
    ]
)
