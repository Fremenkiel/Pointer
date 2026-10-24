// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Model",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Model", targets: ["Model"])],
    targets: [.target(name: "Model")]
)
