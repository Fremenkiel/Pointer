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
        let (bufferIndex, offset) = location(of: block)
        let buffer = buffers[bufferIndex]
        precondition(
            (offset + block.capacity) * Self.bytesPerPoint <= buffer.length,
            "Block \(block) is outside its buffer"
        )
        // Safe: the buffer is shared memory of `buffer.length` bytes, and the preconditions keep
        // the writes inside it. Each slot is one `SIMD2<Float>`, the `float2` of the shader.
        let target = buffer.contents()
            .advanced(by: offset * Self.bytesPerPoint)
            .bindMemory(to: SIMD2<Float>.self, capacity: points.count)
        for (index, point) in points.values.enumerated() {
            target[index] = SIMD2(point.x, point.y)
        }
    }
}
