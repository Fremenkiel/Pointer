import Metal

extension PreviewUploads {
    /// Writes `pixels` from `offset` on into the buffer of the current frame.
    func write(_ pixels: [UInt8], at offset: Int) {
        precondition(
            offset >= 0 && offset + pixels.count <= Self.capacity,
            "Pixels \(offset) to \(offset + pixels.count) out of the buffer"
        )
        assert(buffer.length >= Self.capacity, "The staging buffer holds its capacity")
        // Safe: the buffer holds `capacity` bytes, and the precondition keeps the copy inside.
        let target = buffer.contents().advanced(by: offset)
        pixels.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            target.copyMemory(from: base, byteCount: source.count)
        }
    }
}
