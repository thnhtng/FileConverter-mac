// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FileConverterKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "FileConverterKit",
            targets: ["FileConverterKit"]
        )
    ],
    targets: [
        .target(
            name: "FileConverterKit"
        ),
        .testTarget(
            name: "FileConverterKitTests",
            dependencies: ["FileConverterKit"]
        )
    ]
)
