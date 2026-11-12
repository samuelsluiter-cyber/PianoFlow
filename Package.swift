// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PianoFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PianoFlow", path: "Sources/PianoFlow")
    ]
)
