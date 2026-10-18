import SwiftUI
import Testing
import UIKit

/// Renders a SwiftUI view with `UIGraphicsImageRenderer` and compares it with a reference PNG in
/// `References` (TEST-07). A missing reference is written and the test fails, so that a person
/// reviews the new image.
@MainActor
enum ViewSnapshot {
    /// The part of the pixels that can differ (TEST-07).
    static let tolerance = 0.005
    /// A channel difference up to this value counts as equal. It absorbs text antialiasing.
    static let channelTolerance = 8
    /// True on the simulator. Only the simulator reads the reference PNGs on the Mac, and the
    /// references come from the simulator of `make snapshots`.
    nonisolated static var canReadReferences: Bool {
        #if targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }

    /// The scale of the rendered image, so that the reference does not depend on the screen.
    static let scale: CGFloat = 2

    static func assertMatches(
        _ view: some View,
        named name: String,
        filePath: String = #filePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let image = try render(view)
        let url = URL(filePath: filePath).deletingLastPathComponent()
            .appending(path: "References").appending(path: "\(name).png")
        guard let data = try? Data(contentsOf: url), let reference = UIImage(data: data) else {
            let written = (try? image.pngData()?.write(to: url)) != nil
            Issue.record(
                "No reference \(name).png. Wrote a new one: \(written)",
                sourceLocation: sourceLocation
            )
            return
        }
        let actual = try pixels(image)
        let expected = try pixels(reference)
        guard actual.width == expected.width, actual.height == expected.height else {
            let actualSize = "\(actual.width)x\(actual.height)"
            let expectedSize = "\(expected.width)x\(expected.height)"
            Issue.record(
                "Size \(actualSize) differs from the reference \(expectedSize)",
                sourceLocation: sourceLocation
            )
            return
        }
        var differing = 0
        for pixel in 0..<(actual.width * actual.height) {
            let base = pixel * 4
            if (0..<3).contains(where: {
                abs(Int(actual.bytes[base + $0]) - Int(expected.bytes[base + $0]))
                    > channelTolerance
            }) {
                differing += 1
            }
        }
        let limit = Int(Double(actual.width * actual.height) * tolerance)
        #expect(
            differing <= limit,
            "\(differing) pixels differ from \(name).png",
            sourceLocation: sourceLocation
        )
    }

    /// Lays out the view at its ideal size on black and draws it.
    static func render(_ view: some View) throws -> UIImage {
        let host = UIHostingController(rootView: view.environment(\.colorScheme, .dark))
        host.view.backgroundColor = .black
        // A snapshot has no screen edge, so the safe area of the window must not move the view.
        host.safeAreaRegions = []
        let size = host.sizeThatFits(in: CGSize(width: 1_000, height: 1_000))
        // Only UIApplication reaches the scene of the test host. The product owner allowed this
        // one use in the snapshot helper on 2026-10-18 (D-59, after D-44).
        // swiftlint:disable:next arch_05_singletons
        let scenes = UIApplication.shared.connectedScenes
        let scene = try #require(
            scenes.compactMap { $0 as? UIWindowScene }.first,
            "The test host has no window scene"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            host.view.layer.render(in: context.cgContext)
        }
        window.isHidden = true
        return image
    }

    /// The RGBA bytes of an image in sRGB.
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    private static func pixels(_ image: UIImage) throws -> Pixels {
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(width: width, height: height, bytes: bytes)
    }
}
