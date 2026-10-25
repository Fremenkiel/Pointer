/// The chunks of a list that several threads work on: the split of an erase and the layouts of
/// a load (D-92). One place keeps the numbers, so the two cannot drift apart (TEST-06).
public enum ParallelChunks {
    /// The fewest items of one chunk. A shorter list runs on one thread.
    public static let minimumSize = 64
    /// The most chunks. The iPad Pro (M4) has 4 performance cores and 6 efficiency cores.
    public static let maxCount = 8

    /// Returns the number of chunks of `itemCount` items: one per `minimumSize` items, at least
    /// one and at most `maxCount`.
    ///
    /// - Precondition: `itemCount` is not negative.
    public static func count(of itemCount: Int) -> Int {
        precondition(itemCount >= 0, "An item count is not negative, got \(itemCount)")
        return min(max(itemCount / minimumSize, 1), maxCount)
    }

    /// Returns the range of the items of chunk `index` of `chunkCount` chunks of `itemCount`
    /// items. The chunks cover the items in order, and the last ones can be empty.
    ///
    /// - Precondition: `index` is a chunk, and the counts are not negative.
    public static func range(of index: Int, chunkCount: Int, itemCount: Int) -> Range<Int> {
        precondition((0..<chunkCount).contains(index), "Chunk \(index) of \(chunkCount)")
        precondition(itemCount >= 0, "An item count is not negative, got \(itemCount)")
        let size = (itemCount + chunkCount - 1) / chunkCount
        return min(index * size, itemCount)..<min((index + 1) * size, itemCount)
    }
}
