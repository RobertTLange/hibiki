// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hibiki",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Hibiki", targets: ["Hibiki"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Hibiki",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources/Hibiki",
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("hibiki.png"),
                .copy("Resources/AppIcon.icns"),
                .process("Resources/Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "HibikiTests",
            dependencies: [],
            path: "Tests/HibikiTests"
        )
    ]
)
