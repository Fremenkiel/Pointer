// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../Geometry"),
        .package(path: "../Model"),
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                .product(name: "Geometry", package: "Geometry"),
                .product(name: "Model", package: "Model"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence",
                .product(name: "Geometry", package: "Geometry"),
                .product(name: "Model", package: "Model"),
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
