// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "FormatFactory",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FormatFactoryCore", targets: ["FormatFactoryCore"]),
        .executable(name: "FormatFactoryApp", targets: ["FormatFactoryApp"])
    ],
    targets: [
        .target(
            name: "FormatFactoryCore",
            linkerSettings: [
                .linkedFramework("ImageIO"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("PDFKit"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .executableTarget(
            name: "FormatFactoryApp",
            dependencies: ["FormatFactoryCore"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "FormatFactoryCoreTests",
            dependencies: ["FormatFactoryCore"]
        )
    ]
)
