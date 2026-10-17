import Metal

extension DrawListRing {
    /// Writes one entry into the buffer of the current frame.
    func write(_ entry: StrokeDrawEntry, at position: Int) {
        precondition(position >= 0 && position < capacity, "Entry \(position) out of the draw list")
        // Safe: the buffer holds `capacity` entries, and the precondition keeps the write inside.
        let entries = buffer.contents().bindMemory(to: StrokeDrawEntry.self, capacity: capacity)
        entries[position] = entry
    }
}
