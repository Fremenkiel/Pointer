import CoreGraphics
import Foundation
import ImageIO

/// Decodes a gray PNG preview with ImageIO into one reused buffer of 512 by 512 bytes (D-107,
/// the M6 plan section 4, rule 5). One loader owns one decoder, so one thread uses it at a time.
struct PreviewDecoder {
    /// A decoded preview: its size and its gray pixels, row by row.
    struct Image {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    /// The largest side of a decoded preview.
    static let maxSide = PreviewSlots.sides[0]
    private var buffer = [UInt8](repeating: 0, count: maxSide * maxSide)

    /// Decodes `data` to at most `step` pixels on its longer side.
    ///
    /// - Precondition: `step` is from 1 to `maxSide`.
    /// - Returns: The width, the height, and the gray pixels row by row, or `nil` for data that
    ///   is not an image.
    mutating func decode(_ data: Data, step: Int) -> Image? {
        precondition(step > 0 && step <= Self.maxSide, "Step \(step) is outside the buffer")
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: step,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let width = min(image.width, step)
        let height = min(image.height, step)
        guard width > 0, height > 0, draw(image, width: width, height: height) else { return nil }
        let pixels = Array(buffer[0..<(width * height)])
        return Image(width: width, height: height, pixels: pixels)
    }

    /// Draws `image` into the start of the buffer as `width` by `height` gray pixels.
    private mutating func draw(_ image: CGImage, width: Int, height: Int) -> Bool {
        precondition(width * height <= buffer.count, "The image fits the buffer")
        return buffer.withUnsafeMutableBytes { bytes -> Bool in
            // Safe: the context writes `width * height` bytes, and the precondition keeps them
            // inside the buffer. The context does not outlive this closure.
            guard
                let context = CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
    }
}
