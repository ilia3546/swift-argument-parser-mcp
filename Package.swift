// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-argument-parser-mcp",
    // `platforms` only constrains Apple platforms; Linux is supported via the
    // standard Swift toolchain (CI: Swift 6.0/6.1 on Ubuntu Jammy).
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ArgumentParserMCP",
            targets: ["ArgumentParserMCP"]
        ),
        .executable(
            name: "demo-cli",
            targets: ["demo-cli"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.11.0")
    ],
    targets: [
        .target(
            name: "ArgumentParserMCP",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .executableTarget(
            name: "demo-cli",
            dependencies: [
                .target(name: "ArgumentParserMCP"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "ArgumentParserMCPTests",
            dependencies: [
                .target(name: "ArgumentParserMCP"),
                .target(name: "demo-cli"),
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
    ]
)
