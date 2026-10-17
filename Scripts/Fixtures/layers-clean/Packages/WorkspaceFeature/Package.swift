// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WorkspaceFeature",
    platforms: [.iOS(.v26)],
    products: [.library(name: "WorkspaceFeature", targets: ["WorkspaceFeature"])],
    targets: [.target(name: "WorkspaceFeature")]
)
