// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Rendering",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Rendering", targets: ["Rendering"])
    ],
    dependencies: [
        .package(path: "../Geometry"),
        .package(path: "../InkEngine"),
        .package(path: "../Model"),
    ],
    targets: [
        .target(
            name: "Rendering",
            dependencies: [
                .product(name: "Geometry", package: "Geometry"),
                .product(name: "InkEngine", package: "InkEngine"),
                .product(name: "Model", package: "Model"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        )
    ],
    swiftLanguageModes: [.v6]
)
