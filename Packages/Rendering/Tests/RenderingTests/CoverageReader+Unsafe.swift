import Metal

/// Reads the coverage of a committed-format texture for image comparisons.
enum CoverageReader {
    /// Returns the bytes of a shared `.r8Unorm` texture, row by row.
    ///
    /// - Precondition: The texture is shared and `.r8Unorm`, and no GPU work writes it.
    static func pixels(of texture: any MTLTexture) -> [UInt8] {
        precondition(texture.storageMode == .shared, "Only a shared texture can be read")
        precondition(texture.pixelFormat == .r8Unorm, "Only an r8 texture is coverage")
        var pixels = [UInt8](repeating: 0, count: texture.width * texture.height)
        // Safe: the array holds exactly the bytes of the region, one byte per pixel.
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: texture.width,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return pixels
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
