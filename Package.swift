// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecureChatSDK",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SecureChatSDK",
            targets: ["SecureChatSDK"]
        ),
    ],
    targets: [
        .target(
            name: "SecureChatSDK",
            path: "Sources/SecureChatSDK",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
