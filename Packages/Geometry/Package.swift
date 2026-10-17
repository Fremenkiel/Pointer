// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Geometry",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Geometry", targets: ["Geometry"])
    ],
    targets: [
        .target(
            name: "Geometry",
            swiftSettings: [.treatAllWarnings(as: .error)]
        )
    ],
    swiftLanguageModes: [.v6]
)
