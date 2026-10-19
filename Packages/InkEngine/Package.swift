// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "InkEngine",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "InkEngine", targets: ["InkEngine"])
    ],
    dependencies: [
        .package(path: "../Geometry"),
        .package(path: "../Model"),
    ],
    targets: [
        .target(
            name: "InkEngine",
            dependencies: [
                .product(name: "Geometry", package: "Geometry"),
                .product(name: "Model", package: "Model"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "InkEngineTests",
            dependencies: [
                "InkEngine",
                .product(name: "Geometry", package: "Geometry"),
                .product(name: "Model", package: "Model"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
