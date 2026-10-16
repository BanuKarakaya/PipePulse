// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PipePulse",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PipePulse", targets: ["PipePulse"])
    ],
    targets: [
        .executableTarget(
            name: "PipePulse",
            path: "Sources/PipePulse"
        ),
        .testTarget(
            name: "PipePulseTests",
            dependencies: ["PipePulse"],
            path: "Tests/PipePulseTests"
        )
    ]
)
