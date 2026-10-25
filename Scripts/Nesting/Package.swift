// swift-tools-version:6.2
import PackageDescription

// The nesting check of FLOW-04 (D-174, D-175). A development tool under D-04: the app never links
// it, and SwiftSyntax stays out of the dependency graph of the app.
let package = Package(
    name: "Nesting",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Nesting",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6), .treatAllWarnings(as: .error)]
        )
    ]
)
