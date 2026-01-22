// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tyler",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Tyler", targets: ["Tyler"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Tyler",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources/Tyler",
            exclude: ["Resources/Info.plist"]
        )
    ]
)
