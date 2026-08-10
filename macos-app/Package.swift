// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "COLMAP360Studio",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "COLMAP360Studio", targets: ["COLMAP360Studio"])],
    targets: [
        .executableTarget(
            name: "COLMAP360Studio",
            path: "Sources/COLMAP360Studio"
        )
    ]
)
