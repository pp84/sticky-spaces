// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StickySpaces",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "StickySpaces", path: "Sources/StickySpaces")
    ]
)
