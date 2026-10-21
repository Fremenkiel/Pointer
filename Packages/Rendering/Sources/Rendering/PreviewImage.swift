import CoreGraphics
import Foundation
import ImageIO

/// The preview of a child canvas: gray pixels row by row, white content on black (D-97).
public struct PreviewImage: Sendable, Equatable {
    /// The longest side of a preview in pixels: the largest size step (D-97).
    public static let maxSide = PreviewSlots.sides[0]

    /// The width in pixels.
    public let width: Int
    /// The height in pixels.
    public let height: Int
    /// The gray value of each pixel, row by row.
    public let pixels: [UInt8]

    /// Makes an image.
    ///
    /// - Precondition: `pixels` holds `width * height` values, and both sides are positive.
    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0, "A preview has pixels, got \(width) x \(height)")
        precondition(pixels.count == width * height, "One value per pixel")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The type identifier of PNG. A string, so that `Rendering` needs no other framework than
    /// ImageIO (BUILD-03, D-107).
    private static var pngType: CFString { "public.png" as CFString }

    /// Encodes the image as a gray 8-bit PNG with ImageIO (D-97, D-107).
    ///
    /// - Returns: The PNG bytes, or `nil` if ImageIO fails.
    public func pngData() -> Data? {
        RenderSignpost.begin("PNGEncode")
        defer { RenderSignpost.end("PNGEncode") }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else { return nil }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                Self.pngType,
                1,
                nil
            )
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
