import Metal

extension DrawListRing {
    /// Writes entries from `position` on into the buffer of the current frame.
    func write(_ entries: [StrokeDrawEntry], at position: Int) {
        precondition(
            position >= 0 && position + entries.count <= capacity,
            "Entries \(position) to \(position + entries.count) out of the draw list"
        )
        // Safe: the buffer holds `capacity` entries, and the precondition keeps the copy inside.
        let target = buffer.contents()
            .bindMemory(to: StrokeDrawEntry.self, capacity: capacity)
            .advanced(by: position)
        entries.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            target.update(from: base, count: source.count)
        }
    }
}
