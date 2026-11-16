// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "xcross-icon-compiler",
    products: [
        .executable(name: "xcross-icon", targets: ["XcrossIcon"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/xtool-org/AssetKit.git",
            revision: "e763558b55fcbb5a443b1d7b2c6f0972d8bd14f7"
        ),
    ],
    targets: [
        .executableTarget(
            name: "XcrossIcon",
            dependencies: [
                .product(name: "AssetKit", package: "AssetKit"),
            ]
        ),
    ]
)
