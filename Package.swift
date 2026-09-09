// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZCodeWidget",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.24.0")
    ],
    targets: [
        .executableTarget(
            name: "ZCodeWidget",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/ZCodeWidget"
        )
    ]
)
