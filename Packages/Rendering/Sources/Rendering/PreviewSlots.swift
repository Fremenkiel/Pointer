import Model

/// The slots of the preview atlas: a tree of square slots in four sizes (the M6 plan section 4,
/// rule 2, D-193). A block of 512 pixels holds one preview, or splits into four slots of 256, a
/// slot of 256 splits into four slots of 128, and a slot of 128 into four slots of 64. When no
/// slot fits, the slot that was used least recently goes, and four free siblings join again.
struct PreviewSlots {
    /// The side of a slot at each level, in pixels: 512, 256, 128, and 64.
    static let sides = [512, 256, 128, 64]
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
    /// The last frame that drew each used slot, and `notUsed` for a free or split slot. The
    /// eviction scan thus compares numbers only: a match of the state of each of the 2,720
    /// slots took a quarter of the render thread in a card pan at zoom 1 (D-193).
    private var lastUsed: [[UInt64]]
    /// The last use of a slot that holds no preview.
    private static let notUsed = UInt64.max
    /// The free slots that can take a preview, per level: a free block, or a free child of a
    /// split slot. A split puts its second child last, so a new block fills in order. A scan of
    /// the states took 67 % of the render thread in a card pan once the level of 64 pixels held
    /// 2,048 slots (D-193).
    private var open: [[Int]]
    /// The place of each slot in `open`, or -1 if the slot is not open.
    private var openPlace: [[Int]]

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
        lastUsed = counts.map { [UInt64](repeating: Self.notUsed, count: $0) }
        open = counts.map { count in
            var list: [Int] = []
            list.reserveCapacity(count)
            return list
        }
        openPlace = counts.map { [Int](repeating: -1, count: $0) }
        for index in (0..<blockCount).reversed() {
            addOpen(level: 0, index: index)
        }
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
    /// recently goes, but never a slot that the frame `frame` used, and never the slot of a
    /// card for which `keeping` is `true` (D-193).
    ///
    /// - Precondition: `level` is a level of `sides`.
    /// - Returns: The slot, or `nil` if no slot can go. `evicted` gets the cards whose slots
    ///   went.
    mutating func allocate(
        level: Int,
        for card: CardID,
        frame: UInt64,
        keeping: (CardID) -> Bool = { _ in false },
        evicted: inout [CardID]
    ) -> Slot? {
        precondition(level >= 0 && level < Self.sides.count, "Level \(level)")
        // Each eviction frees one used slot, so the slot count bounds the loop (FLOW-03).
        for _ in 0...slotCount {
            if let slot = takeOpen(at: level) ?? splitDown(to: level) {
                states[slot.level][slot.index] = .used(card)
                lastUsed[slot.level][slot.index] = frame
                return slot
            }
            guard let oldest = leastRecentlyUsed(before: frame, keeping: keeping),
                let owner = owner(of: oldest)
            else { return nil }
            free(oldest)
            evicted.append(owner)
        }
        assertionFailure("The eviction loop passed the slot count")
        return nil
    }

    // Only the tests read it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// The last frame that used `slot`.
    func lastUse(of slot: Slot) -> UInt64 { lastUsed[slot.level][slot.index] }
    // swiftlint:enable unused_declaration

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
        lastUsed[slot.level][slot.index] = Self.notUsed
        var level = slot.level
        var index = slot.index
        // A join climbs one level per step, so the level count bounds the loop (FLOW-03).
        for _ in Self.sides.indices where level > 0 {
            let first = index - index % Self.childCount
            guard states[level][first..<first + Self.childCount].allSatisfy({ $0 == .free }) else {
                break
            }
            for sibling in first..<first + Self.childCount where sibling != index {
                removeOpen(level: level, index: sibling)
            }
            level -= 1
            index /= Self.childCount
            states[level][index] = .free
            assert(lastUsed[level][index] == Self.notUsed, "A split slot has no last use")
        }
        addOpen(level: level, index: index)
    }

    /// Takes the last open slot of `level`, or returns `nil`.
    private mutating func takeOpen(at level: Int) -> Slot? {
        precondition(level >= 0 && level < states.count, "Level \(level)")
        guard let index = open[level].last else { return nil }
        removeOpen(level: level, index: index)
        assert(states[level][index] == .free, "An open slot is free")
        return Slot(level: level, index: index)
    }

    /// Splits the nearest open slot above `level` down to `level`, and returns its first slot.
    /// The other children become open.
    private mutating func splitDown(to level: Int) -> Slot? {
        precondition(level < Self.sides.count, "Level \(level)")
        guard level > 0 else { return nil }
        for upper in stride(from: level - 1, through: 0, by: -1) {
            guard var slot = takeOpen(at: upper) else { continue }
            for _ in upper..<level {
                states[slot.level][slot.index] = .split
                let first = slot.index * Self.childCount
                for child in (first + 1..<first + Self.childCount).reversed() {
                    addOpen(level: slot.level + 1, index: child)
                }
                slot = Slot(level: slot.level + 1, index: first)
            }
            assert(states[slot.level][slot.index] == .free, "A new child is free")
            return slot
        }
        return nil
    }

    /// Adds a free slot to the open slots of its level.
    private mutating func addOpen(level: Int, index: Int) {
        precondition(openPlace[level][index] < 0, "Slot \(index) of level \(level) is open")
        openPlace[level][index] = open[level].count
        open[level].append(index)
    }

    /// Removes a slot from the open slots of its level, with the last one in its place.
    private mutating func removeOpen(level: Int, index: Int) {
        let place = openPlace[level][index]
        precondition(place >= 0, "Slot \(index) of level \(level) is not open")
        let last = open[level].removeLast()
        if last != index {
            open[level][place] = last
            openPlace[level][last] = place
        }
        openPlace[level][index] = -1
    }

    /// Returns the used slot that was drawn least recently, before the frame `frame`, whose
    /// card `keeping` lets go.
    private func leastRecentlyUsed(
        before frame: UInt64,
        keeping: (CardID) -> Bool
    ) -> Slot? {
        precondition(frame > 0, "Frames count from 1")
        var best: Slot?
        // A slot without a preview has the last use `notUsed`, which is never below `frame`.
        var bestFrame = frame
        for level in lastUsed.indices {
            for index in lastUsed[level].indices where lastUsed[level][index] < bestFrame {
                let slot = Slot(level: level, index: index)
                guard let card = owner(of: slot), !keeping(card) else { continue }
                best = slot
                bestFrame = lastUsed[level][index]
            }
        }
        assert(best.map { owner(of: $0) != nil } ?? true, "Only a used slot goes")
        return best
    }
}
