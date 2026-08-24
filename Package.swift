// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Markv",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Markv", targets: ["Markv"])
    ],
    targets: [
        .executableTarget(
            name: "Markv",
            path: "Sources/Markv"
        ),
        .testTarget(
            name: "MarkvTests",
            dependencies: ["Markv"],
            path: "Tests/MarkvTests"
        )
    ]
)
