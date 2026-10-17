// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Model",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Model", targets: ["Model"])],
    dependencies: [.package(path: "../Persistence")],
    targets: [
        .target(
            name: "Model",
            dependencies: [.product(name: "Persistence", package: "Persistence")]
        )
    ]
)
