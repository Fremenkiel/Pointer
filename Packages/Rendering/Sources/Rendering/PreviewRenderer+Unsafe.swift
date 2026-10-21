import Metal

extension PreviewRenderer {
    /// Copies the image of `width` by `height` pixels out of the readback buffer, after the GPU
    /// completed the blit into it.
    ///
    /// - Returns: The image, or `nil` for an empty size.
    func readImage(width: Int, height: Int) -> PreviewImage? {
        guard width > 0, height > 0 else { return nil }
        precondition(width * height <= readback.length, "The image fits the readback buffer")
        // Safe: the buffer holds `side * side` bytes, and the precondition keeps the copy inside.
        let source = readback.contents().bindMemory(to: UInt8.self, capacity: width * height)
        let pixels = Array(UnsafeBufferPointer(start: source, count: width * height))
        return PreviewImage(width: width, height: height, pixels: pixels)
    }
}
