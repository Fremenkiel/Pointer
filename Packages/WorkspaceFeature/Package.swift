// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WorkspaceFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "WorkspaceFeature", targets: ["WorkspaceFeature"])
    ],
    dependencies: [
        .package(path: "../DesignSystem"),
        .package(path: "../Model"),
    ],
    targets: [
        .target(
            name: "WorkspaceFeature",
            dependencies: [
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Model", package: "Model"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "WorkspaceFeatureTests",
            dependencies: [
                "WorkspaceFeature",
                .product(name: "Model", package: "Model"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
