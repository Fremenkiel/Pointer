// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CanvasFeature",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "CanvasFeature", targets: ["CanvasFeature"])
    ],
    dependencies: [
        .package(path: "../DesignSystem"),
        .package(path: "../Geometry"),
        .package(path: "../InkEngine"),
        .package(path: "../Model"),
        .package(path: "../Persistence"),
        .package(path: "../Rendering"),
    ],
    targets: [
        .target(
            name: "CanvasFeature",
            dependencies: [
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Geometry", package: "Geometry"),
                .product(name: "InkEngine", package: "InkEngine"),
                .product(name: "Model", package: "Model"),
                .product(name: "Rendering", package: "Rendering"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "CanvasFeatureTests",
            dependencies: [
                "CanvasFeature",
                .product(name: "Geometry", package: "Geometry"),
                .product(name: "Model", package: "Model"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Rendering", package: "Rendering"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
