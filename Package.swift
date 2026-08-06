// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Devbox",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
    ],
    targets: [
        .executableTarget(
            name: "Devbox",
            dependencies: ["Yams"],
            path: "Sources/Devbox",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
