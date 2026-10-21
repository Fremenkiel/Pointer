import Metal

extension GlyphRing {
    /// Writes glyph quads from `position` on into the buffer of the current frame.
    func write(_ glyphs: [GlyphInstance], at position: Int) {
        precondition(
            position >= 0 && position + glyphs.count <= capacity,
            "Glyphs \(position) to \(position + glyphs.count) out of the buffer"
        )
        assert(
            buffer.length >= capacity * MemoryLayout<GlyphInstance>.stride,
            "The glyph buffer holds its capacity"
        )
        // Safe: the buffer holds `capacity` quads, and the precondition keeps the copy inside.
        let target = buffer.contents()
            .bindMemory(to: GlyphInstance.self, capacity: capacity)
            .advanced(by: position)
        glyphs.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            target.update(from: base, count: source.count)
        }
    }
}
