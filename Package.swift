// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mailroom",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Mailroom",
            path: "Sources/Mailroom",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
