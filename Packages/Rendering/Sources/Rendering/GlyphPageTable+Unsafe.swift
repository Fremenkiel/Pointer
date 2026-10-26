import Metal

extension GlyphPageTable {
    /// Writes the handle of the texture of page `index` into the table.
    ///
    /// - Precondition: `index` is inside the table.
    func set(_ index: Int, _ texture: any MTLTexture) {
        precondition(index >= 0 && index < Self.capacity, "Page \(index) is outside the table")
        assert(
            buffer.length >= Self.capacity * MemoryLayout<MTLResourceID>.stride,
            "The table holds each page"
        )
        // Safe: the buffer holds `capacity` handles, and the precondition keeps the write inside.
        buffer.contents()
            .bindMemory(to: MTLResourceID.self, capacity: Self.capacity)
            .advanced(by: index)
            .pointee = texture.gpuResourceID
    }

    /// Writes a placement at its index in the buffer of places.
    ///
    /// - Precondition: The buffer holds the index.
    func writePlace(_ placement: GlyphAtlas.Placement, at index: Int, in places: any MTLBuffer) {
        let stride = MemoryLayout<GlyphPlace>.stride
        precondition(index >= 0 && (index + 1) * stride <= places.length, "Place \(index) fits")
        // Safe: the precondition keeps the write inside the buffer.
        places.contents()
            .bindMemory(to: GlyphPlace.self, capacity: places.length / stride)
            .advanced(by: index)
            .pointee = GlyphPlace(
                bearing: placement.bearing,
                atlasOrigin: SIMD2(UInt16(placement.origin.x), UInt16(placement.origin.y)),
                atlasSize: SIMD2(UInt16(placement.size.x), UInt16(placement.size.y)),
                page: UInt32(placement.page)
            )
    }

    /// Copies the places of the old buffer into the start of the new one.
    func copyPlaces(from old: any MTLBuffer, to new: any MTLBuffer) {
        precondition(old.length <= new.length, "The new buffer holds the old places")
        // Safe: both buffers are shared memory, and the copy takes the length of the smaller one.
        new.contents().copyMemory(from: old.contents(), byteCount: old.length)
    }
}
