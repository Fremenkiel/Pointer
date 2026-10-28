import Metal
import Model
import os

/// All control points of a canvas in a list of shared `MTLBuffer` objects of fixed size
/// (architecture.md 5.3, D-28).
///
/// A `SlabAllocator` hands out the ranges. Each buffer holds `slabsPerBuffer` whole slabs, so a
/// block never crosses a buffer. The arena grows by one buffer up to the byte budget and never
/// copies the points of a buffer. The GPU reads the points directly, because Apple GPUs share
/// memory with the CPU.
final class PointArena {
    /// The bytes of one point slot: `x` and `y` of `InkPoint` as a `float2`. The shader reads
    /// only these, and they halve the arena against the full point (the M2 fix plan,
    /// phase 4, task 1).
    static let bytesPerPoint = MemoryLayout<SIMD2<Float>>.stride
    /// The bytes of one slab.
    static let bytesPerSlab = SlabAllocator.slabPoints * bytesPerPoint
    /// The bytes of one buffer: 16 MB. A doubling buffer of 192 MB copied its points for 7.4 ms
    /// and held the old and the new buffer at once (the M2 fix plan, phase 4, task 3).
    static let bytesPerBuffer = 16 << 20
    /// The slabs of one full buffer.
    static let maxSlabsPerBuffer = bytesPerBuffer / bytesPerSlab

    /// The GPU that makes the buffers.
    let device: any MTLDevice
    /// The largest size of all buffers together, in bytes.
    let byteBudget: Int
    /// The slabs of each buffer. A budget below one full buffer gives smaller buffers.
    let slabsPerBuffer: Int
    /// The buffers, in slab order.
    private(set) var buffers: [any MTLBuffer] = []
    private var allocator: SlabAllocator
    private let signposter = OSSignposter(subsystem: "dk.saarikivi.pointer", category: "Rendering")

    /// Makes an arena with the buffers that hold `initialSlabs` slabs.
    ///
    /// - Precondition: `initialSlabs >= 1`, and the budget holds them.
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make a buffer.
    init(
        device: any MTLDevice,
        initialSlabs: Int,
        byteBudget: Int,
        slabsPerBuffer: Int = PointArena.maxSlabsPerBuffer
    ) throws(RenderingError) {
        precondition(initialSlabs >= 1, "The arena needs 1 slab, got \(initialSlabs)")
        precondition(slabsPerBuffer >= 1, "A buffer needs 1 slab, got \(slabsPerBuffer)")
        let budgetSlabs = byteBudget / Self.bytesPerSlab
        precondition(initialSlabs <= budgetSlabs, "Budget \(byteBudget) is too small")
        self.device = device
        self.byteBudget = byteBudget
        self.slabsPerBuffer = min(slabsPerBuffer, budgetSlabs)
        allocator = SlabAllocator(slabCount: 0)
        let initialBuffers = (initialSlabs + self.slabsPerBuffer - 1) / self.slabsPerBuffer
        for _ in 0..<initialBuffers {
            guard addBuffer() else {
                throw .resourceUnavailable("point arena of \(initialSlabs) slabs")
            }
        }
        assert(allocator.slabCount >= initialSlabs, "The arena holds the initial slabs")
    }

    /// The bytes in use, rounded up to the size classes.
    var usedBytes: Int { allocator.usedPoints * Self.bytesPerPoint }

    // Only the tests read it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// The number of slabs of all buffers.
    var slabCount: Int { allocator.slabCount }
    // swiftlint:enable unused_declaration

    /// The bytes of all buffers.
    var footprint: Int { allocator.slabCount * Self.bytesPerSlab }

    /// Returns the buffer of a block and the index of its first point in that buffer.
    ///
    /// - Precondition: The block came from this arena.
    func location(of block: ArenaBlock) -> (buffer: Int, offset: Int) {
        let pointsPerBuffer = slabsPerBuffer * SlabAllocator.slabPoints
        let buffer = block.start / pointsPerBuffer
        precondition(buffers.indices.contains(buffer), "Block \(block) is outside the arena")
        let offset = block.start - buffer * pointsPerBuffer
        assert(offset + block.capacity <= pointsPerBuffer, "Block \(block) crosses a buffer")
        return (buffer, offset)
    }

    /// Returns a block for `points` points. It adds a buffer if needed and allowed.
    ///
    /// - Returns: `nil` if the arena is at its budget and holds no free block of the class.
    func allocate(points: Int) -> ArenaBlock? {
        if let block = allocator.allocate(points: points) {
            return block
        }
        // A static name only: an interval with a message built a string at each growth
        // (the M10 plan task 3.6).
        let state = signposter.beginInterval("ArenaGrow")
        defer { signposter.endInterval("ArenaGrow", state) }
        guard addBuffer() else { return nil }
        let block = allocator.allocate(points: points)
        assert(block != nil, "A new buffer must have a free slab")
        return block
    }

    /// Returns a block to the arena. The caller must make sure that no GPU frame still reads it.
    func free(_ block: ArenaBlock) {
        allocator.free(block)
    }

    /// Adds one buffer within the budget. The last buffer can hold fewer slabs.
    private func addBuffer() -> Bool {
        let budgetSlabs = byteBudget / Self.bytesPerSlab
        let slabs = min(slabsPerBuffer, budgetSlabs - allocator.slabCount)
        guard slabs > 0, allocator.slabCount % slabsPerBuffer == 0 else { return false }
        guard
            let buffer = device.makeBuffer(
                length: slabs * Self.bytesPerSlab,
                options: .storageModeShared
            )
        else {
            return false
        }
        buffer.label = "Point arena \(buffers.count)"
        buffers.append(buffer)
        allocator.addSlabs(slabs)
        assert(footprint <= byteBudget, "The arena passed its budget")
        return true
    }
}
