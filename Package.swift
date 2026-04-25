// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VokabelApp",
    defaultLocalization: "de",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "VokabelCore", targets: ["VokabelCore"]),
        .executable(name: "VokabelApp", targets: ["VokabelApp"]),
        .executable(name: "VokabelAppChecks", targets: ["VokabelAppChecks"])
    ],
    targets: [
        .target(
            name: "VokabelCore",
            resources: [
                .process("Resources/DriveConfig.example.json"),
                .process("Resources/MASTER_vokabelheft_norwegisch.csv"),
                .copy("Resources/GoogleOAuthConfig.example.plist")
            ]
        ),
        .executableTarget(
            name: "VokabelApp",
            dependencies: ["VokabelCore"]
        ),
        .executableTarget(
            name: "VokabelAppChecks",
            dependencies: ["VokabelCore"]
        )
    ]
)
