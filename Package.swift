// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Wallflow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Wallflow", path: "Sources/Wallflow")
    ]
)
