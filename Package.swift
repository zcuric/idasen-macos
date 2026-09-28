// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Idasen",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Idasen", targets: ["IdasenApp"]),
        .library(name: "IdasenKit", targets: ["IdasenKit"]),
    ],
    targets: [
        .target(
            name: "IdasenKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "IdasenApp",
            dependencies: ["IdasenKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "IdasenKitTests",
            dependencies: ["IdasenKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
