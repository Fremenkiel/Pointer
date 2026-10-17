import Model

/// Hands out point ranges of fixed size classes from equal slabs (architecture.md 5.3).
///
/// Each slab holds `slabPoints` point slots. A slab serves one size class at a time and splits
/// into equal blocks. A slab with no used block returns to the free list and can serve any class.
struct SlabAllocator {
    /// The point slots per slab. One slab holds the largest stroke.
    static let slabPoints = Limits.maxPointsPerStroke
    /// The smallest size class.
    static let smallestClassPoints = 16
    /// The number of size classes: 16, 32, and so on up to `slabPoints`.
    static let classCount = 11

    private struct Slab {
        var classIndex: Int?
        var freeBlocks: [Int] = []
        var usedCount = 0
    }

    private var slabs: [Slab] = []
    private var freeSlabs: [Int] = []
    private var partialSlabs: [[Int]] = Array(repeating: [], count: classCount)

    /// The number of point slots in use, rounded up to the size classes.
    private(set) var usedPoints = 0

    /// Makes an allocator with `slabCount` free slabs.
    init(slabCount: Int) {
        addSlabs(slabCount)
    }

    /// The number of slabs.
    var slabCount: Int { slabs.count }

    /// Returns the size class of a stroke with `points` points.
    ///
    /// - Precondition: `points` is in `1...slabPoints`.
    static func classIndex(forPoints points: Int) -> Int {
        precondition(points >= 1 && points <= slabPoints, "Block of \(points) points out of range")
        var index = 0
        var capacity = smallestClassPoints
        while capacity < points && index < classCount - 1 {
            capacity *= 2
            index += 1
        }
        assert(capacity >= points, "Class \(index) is too small for \(points) points")
        return index
    }

    /// Returns the point slots of one block of a size class.
    static func classPoints(_ classIndex: Int) -> Int {
        smallestClassPoints << classIndex
    }

    /// Adds free slabs at the end of the arena.
    ///
    /// - Precondition: `count` is zero or positive.
    mutating func addSlabs(_ count: Int) {
        precondition(count >= 0, "Slab count must not be negative, got \(count)")
        let first = slabs.count
        slabs.append(contentsOf: Array(repeating: Slab(), count: count))
        freeSlabs.append(contentsOf: (first..<slabs.count).reversed())
        assert(freeSlabs.count <= slabs.count, "More free slabs than slabs")
    }

    /// Returns a block with room for `points` point slots, or `nil` if no slab is free.
    ///
    /// - Precondition: `points` is in `1...slabPoints`.
    mutating func allocate(points: Int) -> ArenaBlock? {
        let classIndex = Self.classIndex(forPoints: points)
        if partialSlabs[classIndex].isEmpty {
            guard let slab = freeSlabs.popLast() else { return nil }
            assign(slab, to: classIndex)
        }
        guard let slabIndex = partialSlabs[classIndex].last,
            let blockIndex = slabs[slabIndex].freeBlocks.popLast()
        else {
            preconditionFailure("Partial slab list of class \(classIndex) is broken")
        }
        slabs[slabIndex].usedCount += 1
        if slabs[slabIndex].freeBlocks.isEmpty {
            partialSlabs[classIndex].removeLast()
        }
        let capacity = Self.classPoints(classIndex)
        usedPoints += capacity
        return ArenaBlock(
            start: slabIndex * Self.slabPoints + blockIndex * capacity,
            capacity: capacity
        )
    }

    /// Returns a block to the allocator.
    ///
    /// - Precondition: The block came from `allocate(points:)` and is in use.
    mutating func free(_ block: ArenaBlock) {
        let slabIndex = block.start / Self.slabPoints
        precondition(slabs.indices.contains(slabIndex), "Block \(block) is outside the arena")
        guard let classIndex = slabs[slabIndex].classIndex,
            Self.classPoints(classIndex) == block.capacity
        else {
            preconditionFailure("Block \(block) does not match the class of slab \(slabIndex)")
        }
        let wasFull = slabs[slabIndex].freeBlocks.isEmpty
        slabs[slabIndex].freeBlocks.append((block.start % Self.slabPoints) / block.capacity)
        slabs[slabIndex].usedCount -= 1
        usedPoints -= block.capacity
        if wasFull {
            partialSlabs[classIndex].append(slabIndex)
        }
        if slabs[slabIndex].usedCount == 0 {
            release(slabIndex, classIndex: classIndex)
        }
    }

    private mutating func assign(_ slabIndex: Int, to classIndex: Int) {
        precondition(slabs[slabIndex].classIndex == nil, "Slab \(slabIndex) already serves a class")
        let blockCount = Self.slabPoints / Self.classPoints(classIndex)
        assert(blockCount >= 1, "Class \(classIndex) is larger than a slab")
        slabs[slabIndex] = Slab(
            classIndex: classIndex,
            freeBlocks: Array((0..<blockCount).reversed())
        )
        partialSlabs[classIndex].append(slabIndex)
    }

    private mutating func release(_ slabIndex: Int, classIndex: Int) {
        partialSlabs[classIndex].removeAll { $0 == slabIndex }
        slabs[slabIndex] = Slab()
        freeSlabs.append(slabIndex)
    }
}
