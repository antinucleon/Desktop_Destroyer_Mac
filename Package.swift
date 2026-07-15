// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopDestroyer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DesktopDestroyer", targets: ["DesktopDestroyer"])
    ],
    targets: [
        .executableTarget(
            name: "DesktopDestroyer",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
