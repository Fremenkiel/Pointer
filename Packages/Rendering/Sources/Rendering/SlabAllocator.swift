import Foundation
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
    /// The number of size classes.
    static let classCount = 32
    /// The growth from one size class to the next. With powers of two, a stroke of 300 points
    /// took a block of 512 (the M2 fix plan, phase 4, task 2).
    static let classGrowth = 1.25
    /// The points of each size class: `smallestClassPoints` times `classGrowth` per class,
    /// rounded up to a multiple of 16, and `slabPoints` for the last class.
    static let classSizes: [Int] = {
        var sizes = [smallestClassPoints]
        for index in 1..<classCount {
            let grown = Double(smallestClassPoints) * pow(classGrowth, Double(index))
            let rounded = Int((grown / 16).rounded(.up)) * 16
            sizes.append(min(max(rounded, sizes[index - 1] + 16), slabPoints))
        }
        sizes[classCount - 1] = slabPoints
        return sizes
    }()

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
        guard let index = classSizes.firstIndex(where: { $0 >= points }) else {
            preconditionFailure("No size class holds \(points) points")
        }
        return index
    }

    /// Returns the slabs that blocks for strokes of `pointCounts` points fill, with one partial
    /// slab per size class at most. The worst case of all classes took 5.9 MB for 2,000 strokes
    /// of 60 points that need 1.0 MB (review M9 section 3.3, item 4, the M10 plan task 3.4).
    static func slabsNeeded<Counts: Sequence<Int>>(pointCounts: Counts) -> Int {
        var blocks = [Int](repeating: 0, count: classCount)
        for points in pointCounts {
            blocks[classIndex(forPoints: points)] += 1
        }
        var slabs = 0
        for (index, count) in blocks.enumerated() where count > 0 {
            let perSlab = slabPoints / classSizes[index]
            slabs += (count + perSlab - 1) / perSlab
        }
        assert(slabs <= blocks.reduce(0, +), "A block never needs more than one slab")
        return slabs
    }

    /// Returns the point slots of one block of a size class.
    static func classPoints(_ classIndex: Int) -> Int {
        classSizes[classIndex]
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
        // A second free of a block would hand its range to two strokes (review of 2026-10-28).
        precondition(slabs[slabIndex].usedCount > 0, "Block \(block) is not in use")
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
        // The free list of an earlier assignment keeps its storage (M-08). It grows only for a
        // class with more blocks than the slab served before.
        var blocks = slabs[slabIndex].freeBlocks
        slabs[slabIndex].freeBlocks = []
        blocks.removeAll(keepingCapacity: true)
        blocks.append(contentsOf: (0..<blockCount).reversed())
        slabs[slabIndex] = Slab(classIndex: classIndex, freeBlocks: blocks)
        partialSlabs[classIndex].append(slabIndex)
    }

    private mutating func release(_ slabIndex: Int, classIndex: Int) {
        partialSlabs[classIndex].removeAll { $0 == slabIndex }
        // The free list stays for the next assignment (M-08).
        slabs[slabIndex].classIndex = nil
        slabs[slabIndex].usedCount = 0
        freeSlabs.append(slabIndex)
    }
}
