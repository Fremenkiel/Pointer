// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WorkspaceFeature",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "WorkspaceFeature", targets: ["WorkspaceFeature"])
    ],
    dependencies: [
        .package(path: "../DesignSystem"),
        .package(path: "../Model"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "WorkspaceFeature",
            dependencies: [
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Model", package: "Model"),
                .product(name: "Persistence", package: "Persistence")
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        )
    ],
    swiftLanguageModes: [.v6]
)
