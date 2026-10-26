import Metal

extension GlyphRunStore {
    /// Copies the quads of a run into its block.
    ///
    /// - Precondition: The block holds all quads.
    func write(_ quads: [StoredGlyph], to block: ArenaBlock) {
        precondition(quads.count <= block.capacity, "Block \(block) is too small")
        let (index, offset) = location(of: block)
        let buffer = buffers[index]
        precondition(
            (offset + block.capacity) * Self.bytesPerQuad <= buffer.length,
            "Block \(block) is outside its buffer"
        )
        // Safe: the buffer is shared memory of `buffer.length` bytes, and the preconditions keep
        // the copy inside it.
        let target = buffer.contents()
            .bindMemory(to: StoredGlyph.self, capacity: buffer.length / Self.bytesPerQuad)
            .advanced(by: offset)
        quads.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            target.update(from: base, count: source.count)
        }
    }

    /// Writes the GPU address of a buffer into the address table.
    ///
    /// - Precondition: `index` is inside the table.
    func setAddress(of buffer: any MTLBuffer, at index: Int) {
        precondition(index >= 0 && index < Self.maxBuffers, "Buffer \(index) is outside the table")
        // Safe: the table holds `maxBuffers` addresses, and the precondition keeps the write
        // inside it.
        addresses.contents()
            .bindMemory(to: UInt64.self, capacity: Self.maxBuffers)
            .advanced(by: index)
            .pointee = buffer.gpuAddress
    }
}
