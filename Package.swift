// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EtherDot",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Pure logic and artwork: no app lifecycle, so it can be unit tested.
        .target(name: "EtherDotCore"),
        .executableTarget(
            name: "EtherDot",
            dependencies: ["EtherDotCore", .product(name: "Sparkle", package: "Sparkle")]
        ),
        // Renders the app icon, menu bar template and DMG background from code.
        .executableTarget(name: "IconGenerator", dependencies: ["EtherDotCore"]),
        .testTarget(name: "EtherDotCoreTests", dependencies: ["EtherDotCore"]),
    ]
)
