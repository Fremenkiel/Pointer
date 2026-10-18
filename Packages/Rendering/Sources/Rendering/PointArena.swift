import Metal
import Model
import os

/// All control points of a canvas in one shared `MTLBuffer` (architecture.md 5.3, D-28).
///
/// A `SlabAllocator` hands out the ranges. The buffer grows by doubling up to the byte budget.
/// The GPU reads the points directly, because Apple GPUs share memory with the CPU.
final class PointArena {
    /// The bytes of one point slot: `x` and `y` of `InkPoint` as a `float2`. The shader reads
    /// only these, and they halve the arena against the full point (docs/m2-fix-plan.md,
    /// phase 4, task 1).
    static let bytesPerPoint = MemoryLayout<SIMD2<Float>>.stride
    /// The bytes of one slab.
    static let bytesPerSlab = SlabAllocator.slabPoints * bytesPerPoint

    let device: any MTLDevice
    /// The largest size of the buffer, in bytes.
    let byteBudget: Int
    /// The buffer with all points. It changes when the arena grows.
    private(set) var buffer: any MTLBuffer
    private var allocator: SlabAllocator
    private let signposter = OSSignposter(subsystem: "dk.saarikivi.pointer", category: "Rendering")

    /// Makes an arena.
    ///
    /// - Precondition: `initialSlabs >= 1`, and the budget holds them.
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make the buffer.
    init(device: any MTLDevice, initialSlabs: Int, byteBudget: Int) throws(RenderingError) {
        precondition(initialSlabs >= 1, "The arena needs 1 slab, got \(initialSlabs)")
        precondition(
            initialSlabs * Self.bytesPerSlab <= byteBudget,
            "Budget \(byteBudget) is too small"
        )
        guard
            let buffer = device.makeBuffer(
                length: initialSlabs * Self.bytesPerSlab,
                options: .storageModeShared
            )
        else {
            throw .resourceUnavailable("point arena of \(initialSlabs) slabs")
        }
        buffer.label = "Point arena"
        self.device = device
        self.byteBudget = byteBudget
        self.buffer = buffer
        allocator = SlabAllocator(slabCount: initialSlabs)
    }

    /// The bytes in use, rounded up to the size classes.
    var usedBytes: Int { allocator.usedPoints * Self.bytesPerPoint }

    /// The number of slabs of the buffer.
    var slabCount: Int { allocator.slabCount }

    /// Returns a block for `points` points. It grows the buffer if needed and allowed.
    ///
    /// - Returns: `nil` if the arena is at its budget and holds no free block of the class.
    func allocate(points: Int) -> ArenaBlock? {
        if let block = allocator.allocate(points: points) {
            return block
        }
        guard grow() else { return nil }
        let block = allocator.allocate(points: points)
        assert(block != nil, "A grown arena must have a free slab")
        return block
    }

    /// Returns a block to the arena. The caller must make sure that no GPU frame still reads it.
    func free(_ block: ArenaBlock) {
        allocator.free(block)
    }

    private func grow() -> Bool {
        let budgetSlabs = byteBudget / Self.bytesPerSlab
        let newCount = min(allocator.slabCount * 2, budgetSlabs)
        guard newCount > allocator.slabCount else { return false }
        let state = signposter.beginInterval("ArenaGrow", "\(newCount) slabs")
        defer { signposter.endInterval("ArenaGrow", state) }
        guard
            let newBuffer = device.makeBuffer(
                length: newCount * Self.bytesPerSlab,
                options: .storageModeShared
            )
        else {
            return false
        }
        newBuffer.label = "Point arena"
        copyContents(of: buffer, to: newBuffer)
        allocator.addSlabs(newCount - allocator.slabCount)
        buffer = newBuffer
        return true
    }
}
