// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlopEDTKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "FlopEDTKit", targets: ["FlopEDTKit"])
    ],
    targets: [
        .target(
            name: "FlopEDTKit",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FlopEDTKitTests",
            dependencies: ["FlopEDTKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
