// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Library",
    products: [.library(name: "Library", targets: ["Library"])],
    targets: [.target(name: "Library")]
)
