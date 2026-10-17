import Metal

extension CanvasRenderer {
    /// Reads the BGRA bytes of a shared texture.
    func readPixels(of texture: any MTLTexture) -> [UInt8] {
        precondition(texture.storageMode == .shared, "Only a shared texture can be read")
        precondition(texture.pixelFormat == .bgra8Unorm, "Only a BGRA texture can be read")
        let bytesPerRow = texture.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        // Safe: the array holds exactly the bytes of the region, and the GPU work is complete.
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return pixels
    }
}
