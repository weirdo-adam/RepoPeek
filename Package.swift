// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RepoPeek",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "RepoPeekCore", targets: ["RepoPeekCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-log", from: "1.8.0"),
        .package(url: "https://github.com/onevcat/Kingfisher", from: "8.6.0"),
        .package(url: "https://github.com/apple/swift-markdown", from: "0.7.3"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
    ],
    targets: [
        .target(
            name: "RepoPeekCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .executableTarget(
            name: "RepoPeek",
            dependencies: [
                "RepoPeekCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "Logging", package: "swift-log"),
            ],
            exclude: [
                "Resources/Info.plist",
                "Resources/MenuBarIconTemplate.png",
                "Resources/MenuBarIconStanding.png",
                "Resources/MenuBarIconStanding0.png",
                "Resources/MenuBarIconStanding1.png",
                "Resources/MenuBarIconStanding2.png",
                "Resources/MenuBarIconCrouching0.png",
                "Resources/MenuBarIconCrouching1.png",
                "Resources/MenuBarIconLooking0.png",
                "Resources/MenuBarIconLooking1.png",
                "Resources/MenuBarIconRunning0.png",
                "Resources/MenuBarIconRunning1.png",
                "Resources/MenuBarIconRunning2.png",
                "Resources/MenuBarIconRunning3.png",
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/RepoPeek/Resources/Info.plist",
                ]),
                ]),
        .testTarget(
            name: "RepoPeekTests",
            dependencies: ["RepoPeek", "RepoPeekCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
    ])
