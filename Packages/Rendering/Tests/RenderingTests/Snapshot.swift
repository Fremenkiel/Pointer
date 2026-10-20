import Foundation
import Rendering
import Testing
import UIKit

/// Compares a rendered image with a reference PNG in `References` (TEST-07).
///
/// The references are resources of the `PointerDeviceTests` bundle and come from the iPad (D-77).
/// A missing reference fails the test and attaches the new image, so that a person reviews it and
/// copies it into `References`.
enum Snapshot {
    /// The part of the pixels that can differ (TEST-07).
    static let tolerance = 0.005
    /// A channel difference up to this value counts as equal. It absorbs GPU rounding.
    static let channelTolerance = 2

    static func assertMatches(
        _ image: RenderedImage,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let url = Bundle(for: BundleToken.self).url(forResource: name, withExtension: "png")
        guard let url, let reference = try? Data(contentsOf: url), let expected = decode(reference)
        else {
            attach(image, named: name, sourceLocation: sourceLocation)
            Issue.record(
                "No reference \(name).png. The new image is attached.",
                sourceLocation: sourceLocation
            )
            return
        }
        guard expected.width == image.width, expected.height == image.height else {
            Issue.record(
                "Size \(image.width)x\(image.height) differs from the reference",
                sourceLocation: sourceLocation
            )
            return
        }
        let differing = differingPixels(image, expected)
        let limit = Int(Double(image.width * image.height) * tolerance)
        #expect(
            differing <= limit,
            "\(differing) pixels differ from \(name).png",
            sourceLocation: sourceLocation
        )
        if differing > limit { attach(image, named: name, sourceLocation: sourceLocation) }
    }

    /// Attaches the image to the test result as `name.png`.
    private static func attach(
        _ image: RenderedImage,
        named name: String,
        sourceLocation: SourceLocation
    ) {
        guard let data = try? encode(image) else { return }
        Attachment.record(data, named: "\(name).png", sourceLocation: sourceLocation)
    }

    static func differingPixels(_ first: RenderedImage, _ second: RenderedImage) -> Int {
        var count = 0
        for pixel in 0..<(first.width * first.height) {
            let base = pixel * 4
            let differs = (0..<3).contains {
                abs(Int(first.pixels[base + $0]) - Int(second.pixels[base + $0])) > channelTolerance
            }
            if differs { count += 1 }
        }
        return count
    }

    static func encode(_ image: RenderedImage) throws -> Data {
        let cgImage = try #require(makeImage(image))
        return try #require(UIImage(cgImage: cgImage).pngData())
    }

    static func decode(_ data: Data) -> RenderedImage? {
        guard let source = UIImage(data: data)?.cgImage,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: source.width,
                height: source.height,
                bitsPerComponent: 8,
                bytesPerRow: source.width * 4,
                space: space,
                bitmapInfo: bitmapInfo
            )
        else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let bytes = context.makeImage()?.dataProvider?.data as Data? else { return nil }
        return RenderedImage(width: source.width, height: source.height, pixels: Array(bytes))
    }

    private static let bitmapInfo =
        CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    private static func makeImage(_ image: RenderedImage) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(image.pixels) as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: image.width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

/// A class of the test bundle, so that `Bundle(for:)` finds the bundle of the references.
private final class BundleToken {}
