// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hibiki",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Hibiki", targets: ["Hibiki"]),
        .executable(name: "hibiki-cli", targets: ["HibikiCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "HibikiPocketRuntime",
            dependencies: [],
            path: "Sources/HibikiPocketRuntime"
        ),
        .executableTarget(
            name: "Hibiki",
            dependencies: ["KeyboardShortcuts", "HibikiPocketRuntime"],
            path: "Sources/Hibiki",
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("hibiki.png"),
                .copy("Resources/AppIcon.icns"),
                .process("Resources/Assets.xcassets")
            ]
        ),
        .target(
            name: "HibikiCLICore",
            dependencies: [],
            path: "Sources/HibikiCLICore"
        ),
        .testTarget(
            name: "HibikiTests",
            dependencies: ["HibikiPocketRuntime", "HibikiCLICore"],
            path: "Tests/HibikiTests"
        ),
        .executableTarget(
            name: "HibikiCLI",
            dependencies: [
                "HibikiCLICore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/HibikiCLI"
        )
    ]
)
