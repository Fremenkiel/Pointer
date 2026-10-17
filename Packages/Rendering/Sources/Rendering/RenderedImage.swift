/// A rendered image in memory: 8-bit BGRA rows, top row first.
public struct RenderedImage: Sendable {
    /// The width in pixels.
    public let width: Int
    /// The height in pixels.
    public let height: Int
    /// The pixel bytes, 4 per pixel, in BGRA order.
    public let pixels: [UInt8]

    /// Makes an image.
    ///
    /// - Precondition: `pixels` holds `width * height * 4` bytes.
    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(
            pixels.count == width * height * 4,
            "Image of \(width) x \(height) has \(pixels.count) bytes"
        )
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Returns the green value of a pixel. Ink is gray, so one channel is enough.
    ///
    /// - Precondition: The pixel is inside the image.
    public func gray(x: Int, y: Int) -> UInt8 {
        precondition(
            x >= 0 && x < width && y >= 0 && y < height,
            "Pixel (\(x), \(y)) is outside the image"
        )
        return pixels[(y * width + x) * 4 + 1]
    }
}
