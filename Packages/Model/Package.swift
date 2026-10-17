// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Model",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Model", targets: ["Model"])
    ],
    dependencies: [
        .package(path: "../Geometry")
    ],
    targets: [
        .target(
            name: "Model",
            dependencies: [
                .product(name: "Geometry", package: "Geometry")
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "ModelTests",
            dependencies: ["Model", .product(name: "Geometry", package: "Geometry")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
