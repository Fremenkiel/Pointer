import Metal
import Testing

@testable import Rendering

/// Reads the pixels of a drawable after its frame, for the snapshot tests of the frame loop.
@MainActor
enum DrawableCapture {
    /// Copies a drawable texture on the queue of the renderer, after its frame, and reads it.
    ///
    /// - Returns: The BGRA bytes, top row first.
    static func read(_ texture: any MTLTexture, renderer: CanvasRenderer) throws -> [UInt8] {
        let queue = renderer.engine.withRenderer { $0.resources.queue }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        let copy = try #require(queue.device.makeTexture(descriptor: descriptor))
        let commandBuffer = try #require(queue.makeCommandBuffer())
        let blit = try #require(commandBuffer.makeBlitCommandEncoder())
        blit.copy(from: texture, to: copy)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: copy.width * copy.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            copy.getBytes(
                base,
                bytesPerRow: copy.width * 4,
                from: MTLRegionMake2D(0, 0, copy.width, copy.height),
                mipmapLevel: 0
            )
        }
        return pixels
    }
}
