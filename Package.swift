// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Synapse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Synapse", targets: ["Synapse"]),
        .executable(name: "SynapseVoice", targets: ["SynapseVoice"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Synapse",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("CoreServices")
            ]
        ),
        .executableTarget(
            name: "SynapseVoice",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "SynapseTests",
            dependencies: [
                "Synapse",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
