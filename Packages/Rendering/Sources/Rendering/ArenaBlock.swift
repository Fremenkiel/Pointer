/// A range of point slots in the point arena that one stroke owns.
public struct ArenaBlock: Hashable, Sendable {
    /// The index of the first point slot.
    public let start: Int
    /// The number of point slots. It is a size class of `SlabAllocator`.
    public let capacity: Int

    /// Makes a block.
    public init(start: Int, capacity: Int) {
        self.start = start
        self.capacity = capacity
    }
}
