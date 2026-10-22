import Dispatch
import Metal

extension PreviewRenderer {
    /// Carries the readback buffer of one preview to the completion handler of the GPU.
    ///
    /// Safe: the caller made the buffer for this one preview and keeps no reference to it, so
    /// the handler is its only owner. Metal allows a buffer on any thread, and the handler reads
    /// the bytes after the GPU completed the blit into them. The box never leaves this file.
    private struct ReadbackBox: @unchecked Sendable {
        let buffer: any MTLBuffer
    }

    /// Reads the image of `width` by `height` pixels out of `readback` when the GPU completes
    /// `commandBuffer`, and gives it to `completion` off the render thread. A buffer that fails
    /// gives `nil`.
    ///
    /// - Precondition: `readback` is new for this preview, and holds the image.
    static func readOnCompletion(
        of commandBuffer: any MTLCommandBuffer,
        from readback: any MTLBuffer,
        width: Int,
        height: Int,
        completion: @escaping @Sendable (PreviewImage?) -> Void
    ) {
        precondition(width > 0 && height > 0, "A preview has pixels, got \(width) by \(height)")
        precondition(width * height <= readback.length, "The image fits the readback buffer")
        let box = ReadbackBox(buffer: readback)
        commandBuffer.addCompletedHandler { buffer in
            // In the background, iOS refuses work on the GPU, and the buffer ends with an error.
            let image =
                buffer.status == .completed
                ? readImage(of: box.buffer, width: width, height: height) : nil
            DispatchQueue.global(qos: .utility).async { completion(image) }
        }
    }

    /// Copies the image of `width` by `height` pixels out of the readback buffer, after the GPU
    /// completed the blit into it.
    ///
    /// - Returns: The image, or `nil` for an empty size.
    func readImage(width: Int, height: Int) -> PreviewImage? {
        Self.readImage(of: readback, width: width, height: height)
    }

    /// Copies the image of `width` by `height` pixels out of `buffer`.
    private static func readImage(
        of buffer: any MTLBuffer,
        width: Int,
        height: Int
    ) -> PreviewImage? {
        guard width > 0, height > 0 else { return nil }
        precondition(width * height <= buffer.length, "The image fits the readback buffer")
        // Safe: the precondition keeps the copy inside the buffer.
        let source = buffer.contents().bindMemory(to: UInt8.self, capacity: width * height)
        let pixels = Array(UnsafeBufferPointer(start: source, count: width * height))
        return PreviewImage(width: width, height: height, pixels: pixels)
    }
}
