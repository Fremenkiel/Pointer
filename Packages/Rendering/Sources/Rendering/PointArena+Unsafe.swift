import Metal
import Model

extension PointArena {
    /// Copies the points of a stroke into its block.
    ///
    /// - Precondition: The block holds all points.
    func write(_ points: InkPoints, to block: ArenaBlock) {
        precondition(
            points.count <= block.capacity,
            "Block \(block) is too small for \(points.count) points"
        )
        precondition(
            (block.start + block.capacity) * Self.bytesPerPoint <= buffer.length,
            "Block \(block) is outside the arena"
        )
        // Safe: the buffer is shared memory of `buffer.length` bytes, and the preconditions keep
        // the writes inside it. Each slot is one `SIMD2<Float>`, the `float2` of the shader.
        let target = buffer.contents()
            .advanced(by: block.start * Self.bytesPerPoint)
            .bindMemory(to: SIMD2<Float>.self, capacity: points.count)
        for (index, point) in points.values.enumerated() {
            target[index] = SIMD2(point.x, point.y)
        }
    }

    /// Copies the whole old buffer to the start of the new buffer.
    func copyContents(of old: any MTLBuffer, to new: any MTLBuffer) {
        precondition(new.length >= old.length, "The new arena is smaller than the old one")
        // Safe: both buffers are shared memory, and the new buffer is at least as long.
        new.contents().copyMemory(from: old.contents(), byteCount: old.length)
    }
}
