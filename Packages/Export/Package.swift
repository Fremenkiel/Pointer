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
        .package(path: "../Model"),
        .package(path: "../Rendering"),
    ],
    targets: [
        .target(
            name: "Export",
            dependencies: [
                .product(name: "Geometry", package: "Geometry"),
                .product(name: "Model", package: "Model"),
                .product(name: "Rendering", package: "Rendering"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "ExportTests",
            dependencies: [
                "Export",
                .product(name: "Geometry", package: "Geometry"),
                .product(name: "Model", package: "Model"),
                .product(name: "Rendering", package: "Rendering"),
            ],
            exclude: ["References"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
