import Metal

/// Reads the coverage of a committed-format texture for image comparisons.
enum CoverageReader {
    /// Returns one channel of a shared `.r8Unorm` or `.rg8Unorm` texture, row by row: the ink
    /// coverage (channel 0) or the text coverage (channel 1) of a committed texture (D-82).
    ///
    /// - Precondition: The texture is shared, `.r8Unorm` or `.rg8Unorm`, and has the channel, and
    ///   no GPU work writes it.
    static func pixels(of texture: any MTLTexture, channel: Int = 0) -> [UInt8] {
        precondition(texture.storageMode == .shared, "Only a shared texture can be read")
        let channels = texture.pixelFormat == .rg8Unorm ? 2 : 1
        precondition(
            texture.pixelFormat == .r8Unorm || texture.pixelFormat == .rg8Unorm,
            "Only an r8 or an rg8 texture is coverage"
        )
        precondition(channel >= 0 && channel < channels, "The texture has no channel \(channel)")
        let count = texture.width * texture.height
        var bytes = [UInt8](repeating: 0, count: count * channels)
        // Safe: the array holds exactly the bytes of the region, `channels` bytes per pixel.
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: texture.width * channels,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        guard channels > 1 else { return bytes }
        return (0..<count).map { bytes[$0 * channels + channel] }
    }

    /// Returns the largest difference between two images of the same size.
    ///
    /// - Precondition: Both images have the same number of pixels.
    static func largestDifference(_ first: [UInt8], _ second: [UInt8]) -> Int {
        precondition(first.count == second.count, "Images differ in size")
        var largest = 0
        for index in first.indices {
            largest = max(largest, abs(Int(first[index]) - Int(second[index])))
        }
        return largest
    }
}
