// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tokade",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tokade",
            path: "Sources/Tokade",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "TokadeTests",
            dependencies: ["Tokade"],
            path: "Tests/TokadeTests"
        )
    ]
)
