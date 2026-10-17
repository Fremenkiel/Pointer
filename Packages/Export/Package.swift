// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Export",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Export", targets: ["Export"])
    ],
    dependencies: [
        .package(path: "../Geometry"),
        .package(path: "../InkEngine"),
        .package(path: "../Model"),
    ],
    targets: [
        .target(
            name: "Export",
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
