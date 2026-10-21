import Model

/// The slots of the preview atlas: a tree of square slots in three sizes (m6-plan.md section 4,
/// rule 2). A block of 512 pixels holds one preview, or splits into four slots of 256, and a
/// slot of 256 splits into four slots of 128. When no slot fits, the slot that was used least
/// recently goes, and four free siblings join again.
struct PreviewSlots {
    /// The side of a slot at each level, in pixels: 512, 256, and 128.
    static let sides = [512, 256, 128]
    /// The children of a split slot.
    static let childCount = 4

    /// One slot: its level in `sides` and its index at that level.
    struct Slot: Hashable, Sendable {
        let level: Int
        let index: Int
    }

    /// The state of one slot.
    enum State: Equatable {
        /// The slot holds nothing. A slot below the top level counts only if its parent is split.
        case free
        /// The four children of the slot hold the previews.
        case split
        /// The slot holds the preview of one card.
        case used(CardID)
    }

    /// The blocks of 512 pixels per row of the atlas.
    let columns: Int
    /// The blocks of 512 pixels in the atlas.
    let blockCount: Int
    private(set) var states: [[State]]
    private var lastUsed: [[UInt64]]

    /// Makes the slots of an atlas with `blockCount` blocks in rows of `columns`.
    ///
    /// - Precondition: Both counts are positive, and `columns` divides `blockCount`.
    init(blockCount: Int, columns: Int) {
        precondition(blockCount > 0 && columns > 0, "An atlas holds blocks, got \(blockCount)")
        precondition(blockCount.isMultiple(of: columns), "The blocks fill whole rows")
        self.blockCount = blockCount
        self.columns = columns
        var counts: [Int] = []
        var count = blockCount
        for _ in Self.sides {
            counts.append(count)
            count *= Self.childCount
        }
        states = counts.map { [State](repeating: .free, count: $0) }
        lastUsed = counts.map { [UInt64](repeating: 0, count: $0) }
        assert(states.count == Self.sides.count, "One state list per level")
    }

    /// The number of slots at all levels: the bound of the eviction loop.
    var slotCount: Int { states.reduce(0) { $0 + $1.count } }

    /// Returns the top-left pixel of a slot in the atlas.
    func origin(of slot: Slot) -> (x: Int, y: Int) {
        precondition(slot.level >= 0 && slot.level < Self.sides.count, "Level \(slot.level)")
        let block = slot.index >> (2 * slot.level)
        var x = (block % columns) * Self.sides[0]
        var y = (block / columns) * Self.sides[0]
        for level in stride(from: 1, through: slot.level, by: 1) {
            let quarter = (slot.index >> (2 * (slot.level - level))) % Self.childCount
            x += (quarter % 2) * Self.sides[level]
            y += (quarter / 2) * Self.sides[level]
        }
        assert(x >= 0 && y >= 0, "A slot lies in the atlas")
        return (x, y)
    }

    /// Returns the owner of a slot, or `nil` for a slot that holds no preview.
    func owner(of slot: Slot) -> CardID? {
        guard case .used(let card) = states[slot.level][slot.index] else { return nil }
        return card
    }

    /// Takes a slot of `level` for `card`. If no slot fits, the slot that was used least
    /// recently goes, but never a slot that the frame `frame` used.
    ///
    /// - Precondition: `level` is a level of `sides`.
    /// - Returns: The slot, or `nil` if each slot is in use in this frame. `evicted` gets the
    ///   cards whose slots went.
    mutating func allocate(
        level: Int,
        for card: CardID,
        frame: UInt64,
        evicted: inout [CardID]
    ) -> Slot? {
        precondition(level >= 0 && level < Self.sides.count, "Level \(level)")
        // Each eviction frees one used slot, so the slot count bounds the loop (FLOW-03).
        for _ in 0...slotCount {
            if let slot = freeSlot(at: level) ?? splitDown(to: level) {
                states[slot.level][slot.index] = .used(card)
                lastUsed[slot.level][slot.index] = frame
                return slot
            }
            guard let oldest = leastRecentlyUsed(before: frame), let owner = owner(of: oldest)
            else { return nil }
            free(oldest)
            evicted.append(owner)
        }
        assertionFailure("The eviction loop passed the slot count")
        return nil
    }

    /// Notes that the frame `frame` drew the preview of `slot`.
    mutating func markUsed(_ slot: Slot, frame: UInt64) {
        assert(owner(of: slot) != nil, "Only a used slot is drawn")
        lastUsed[slot.level][slot.index] = frame
    }

    /// Frees a slot and joins free siblings into their parent.
    mutating func free(_ slot: Slot) {
        precondition(slot.level >= 0 && slot.level < states.count, "Level \(slot.level)")
        precondition(owner(of: slot) != nil, "Slot \(slot) holds no preview")
        states[slot.level][slot.index] = .free
        var level = slot.level
        var index = slot.index
        // A join climbs one level per step, so the level count bounds the loop (FLOW-03).
        for _ in Self.sides.indices where level > 0 {
            let first = index - index % Self.childCount
            guard states[level][first..<first + Self.childCount].allSatisfy({ $0 == .free }) else {
                return
            }
            level -= 1
            index /= Self.childCount
            states[level][index] = .free
        }
    }

    /// Returns a free slot of `level` whose parent is split, or a free block at the top level.
    private func freeSlot(at level: Int) -> Slot? {
        precondition(level >= 0 && level < states.count, "Level \(level)")
        for index in states[level].indices where states[level][index] == .free {
            if level == 0 || states[level - 1][index / Self.childCount] == .split {
                return Slot(level: level, index: index)
            }
        }
        return nil
    }

    /// Splits the nearest free slot above `level` down to `level`, and returns its first slot.
    private mutating func splitDown(to level: Int) -> Slot? {
        precondition(level < Self.sides.count, "Level \(level)")
        guard level > 0 else { return nil }
        for upper in stride(from: level - 1, through: 0, by: -1) {
            guard var slot = freeSlot(at: upper) else { continue }
            for _ in upper..<level {
                states[slot.level][slot.index] = .split
                slot = Slot(level: slot.level + 1, index: slot.index * Self.childCount)
            }
            assert(states[slot.level][slot.index] == .free, "A new child is free")
            return slot
        }
        return nil
    }

    /// Returns the used slot that was drawn least recently, before the frame `frame`.
    private func leastRecentlyUsed(before frame: UInt64) -> Slot? {
        precondition(frame > 0, "Frames count from 1")
        var best: Slot?
        var bestFrame = UInt64.max
        for level in states.indices {
            for index in states[level].indices where lastUsed[level][index] < bestFrame {
                guard case .used = states[level][index], lastUsed[level][index] < frame else {
                    continue
                }
                best = Slot(level: level, index: index)
                bestFrame = lastUsed[level][index]
            }
        }
        assert(best.map { owner(of: $0) != nil } ?? true, "Only a used slot goes")
        return best
    }
}
