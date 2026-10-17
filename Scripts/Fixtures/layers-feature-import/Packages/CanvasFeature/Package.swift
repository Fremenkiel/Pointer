// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CanvasFeature",
    platforms: [.iOS(.v26)],
    products: [.library(name: "CanvasFeature", targets: ["CanvasFeature"])],
    dependencies: [.package(path: "../WorkspaceFeature")],
    targets: [
        .target(
            name: "CanvasFeature",
            dependencies: [.product(name: "WorkspaceFeature", package: "WorkspaceFeature")]
        )
    ]
)
