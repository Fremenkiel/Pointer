import Geometry
import Model
import os

/// The strokes that the renderer knows, their arena blocks, and their spatial index.
///
/// The renderer keeps its own GPU state and receives only new strokes (data-model.md 8). A
/// stroke can leave the arena when the arena is at its budget. The next draw then copies its
/// points in again from `InkPoints`.
final class StrokeStore {
    /// The side length of a grid cell, in canvas points (architecture.md 5.6).
    static let gridCellSize = 512.0
    /// A stroke that a frame drew stays in the arena for this many frames, because the GPU can
    /// still read it. The draw-list ring lets at most this many frames wait for the GPU.
    static let framesInFlight = UInt64(DrawListRing.bufferCount)
    /// The eviction frees this part of the budget beyond the request, so that a pan at the edge
    /// does not evict and load the same strokes again.
    static let evictionMargin = 0.1

    /// The draw data of one stroke: plain values only, so the per-frame loop copies no
    /// references and does no reference counting (PERF-01).
    ///
    /// The stored fields take 48 bytes per stroke: 32-bit indices and the size class of the
    /// block instead of its capacity. The M2 layout took 80 bytes (docs/m2-fix-plan.md, phase
    /// 4, task 5).
    struct DrawInfo {
        let origin: Point
        var lastDrawnFrame: UInt64 = 0
        let radius: Float
        private let storedPointCount: Int32
        private let storedFirstBlock: Int32
        private var blockStart: Int32 = -1
        private var storedResidentIndex: Int32 = -1
        private let storedBlockCount: UInt16
        private var blockClass: UInt8 = 0
        /// `true` after a draw. The clock sweep clears it once before it evicts the stroke.
        var isReferenced = false

        /// Makes the draw data of a stroke without a block.
        ///
        /// - Precondition: The values fit into the stored fields.
        init(origin: Point, radius: Float, pointCount: Int, firstBlock: Int, blockCount: Int) {
            precondition(pointCount >= 2 && pointCount <= Limits.maxPointsPerStroke, "Bad count")
            precondition(firstBlock >= 0 && firstBlock <= Int(Int32.max), "Block index too large")
            precondition(blockCount >= 1 && blockCount <= Int(UInt16.max), "Bad block count")
            self.origin = origin
            self.radius = radius
            storedPointCount = Int32(pointCount)
            storedFirstBlock = Int32(firstBlock)
            storedBlockCount = UInt16(blockCount)
        }

        /// The control points of the stroke.
        var pointCount: Int { Int(storedPointCount) }
        /// The index of the first block spacing of the stroke in `blockSpacings`.
        var firstBlock: Int { Int(storedFirstBlock) }
        /// The number of blocks of the stroke (`DetailRuns`).
        var blockCount: Int { Int(storedBlockCount) }

        /// The arena block of the stroke, or `nil` if its points are not in the arena.
        var block: ArenaBlock? {
            get {
                guard blockStart >= 0 else { return nil }
                let capacity = SlabAllocator.classPoints(Int(blockClass))
                return ArenaBlock(start: Int(blockStart), capacity: capacity)
            }
            set {
                guard let newValue else {
                    blockStart = -1
                    return
                }
                precondition(newValue.start <= Int(Int32.max), "Block \(newValue) is too far")
                blockStart = Int32(newValue.start)
                blockClass = UInt8(SlabAllocator.classIndex(forPoints: newValue.capacity))
                assert(block == newValue, "The stored block differs from \(newValue)")
            }
        }

        /// The index of the stroke in `residentSlots`, or -1 if the stroke has no block.
        var residentIndex: Int {
            get { Int(storedResidentIndex) }
            set {
                precondition(newValue >= -1 && newValue <= Int(Int32.max), "Bad index")
                storedResidentIndex = Int32(newValue)
            }
        }
    }

    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Rendering")
    private(set) var infos: [DrawInfo] = []
    /// The points by slot, one reference each. Only an upload into the arena and the bend read
    /// them. A full `Stroke` per slot took 128 bytes.
    private var points: [InkPoints] = []
    private var slotByID: [StrokeID: Int] = [:]
    /// The spacing of each block of each stroke.
    private var blockSpacings: [BlockSpacing] = []
    /// The bend of each block, measured at the first draw that needs it. NaN until then.
    private var blockBends: [Float] = []
    private(set) var grid = SpatialGrid<Int>(cellSize: gridCellSize)
    /// The slots of the strokes with an arena block, in no order. The clock sweep walks it.
    private var residentSlots: [Int] = []
    /// The position of the clock hand in `residentSlots`.
    private var clockHand = 0
    let arena: PointArena

    /// Makes an empty store.
    init(arena: PointArena) {
        // The arrays grow with the canvas. A reserve for the stroke limit took about 40 MB for
        // every canvas (docs/m2-fix-plan.md, phase 4, task 5).
        self.arena = arena
    }

    /// The number of strokes.
    var count: Int { infos.count }

    /// Adds a stroke and returns its slot. A stroke that the store holds keeps its slot.
    ///
    /// - Precondition: The store holds fewer than `Limits.maxStrokesPerCanvas` strokes.
    @discardableResult  // The handoff needs the slot. The load path does not.
    func add(_ stroke: Stroke) -> Int {
        if let slot = slotByID[stroke.id] { return slot }
        precondition(
            infos.count < Limits.maxStrokesPerCanvas,
            "The renderer holds the stroke limit"
        )
        let slot = infos.count
        let firstBlock = blockSpacings.count
        BlockSpacing.append(of: stroke.points, to: &blockSpacings)
        blockBends.append(contentsOf: repeatElement(.nan, count: blockSpacings.count - firstBlock))
        let info = DrawInfo(
            origin: stroke.origin,
            radius: stroke.width / 2,
            pointCount: stroke.points.count,
            firstBlock: firstBlock,
            blockCount: blockSpacings.count - firstBlock
        )
        infos.append(info)
        points.append(stroke.points)
        slotByID[stroke.id] = slot
        grid.insert(slot, bounds: stroke.bounds)
        assert(infos.count == grid.count && points.count == infos.count, "Store arrays disagree")
        return slot
    }

    /// Returns the draw data of a stroke with its arena block, and copies the points in if needed.
    ///
    /// - Returns: `nil` if the arena has no room even after eviction. The caller skips the stroke.
    func residentInfo(of slot: Int, frame: UInt64) -> DrawInfo? {
        precondition(infos.indices.contains(slot), "Stroke slot \(slot) does not exist")
        infos[slot].lastDrawnFrame = frame
        infos[slot].isReferenced = true
        let info = infos[slot]
        if info.block != nil { return info }
        let strokePoints = points[slot]
        guard
            let block = arena.allocate(points: strokePoints.count)
                ?? evictAndAllocate(strokePoints.count, frame)
        else {
            logger.error(
                "Point arena is full. A stroke of \(strokePoints.count) points is not drawn."
            )
            return nil
        }
        arena.write(strokePoints, to: block)
        infos[slot].block = block
        infos[slot].residentIndex = residentSlots.count
        residentSlots.append(slot)
        assert(block.capacity >= info.pointCount, "Block \(block) is too small for slot \(slot)")
        return infos[slot]
    }

    /// Frees blocks with a clock sweep until the arena is below its eviction target, then
    /// allocates. A sort of all strokes by their last frame took 4.2 ms with 200,000 strokes
    /// (docs/m2-fix-plan.md, phase 4, task 4).
    ///
    /// The hand walks the resident strokes. It skips a stroke that a frame in flight can still
    /// read, gives a stroke drawn since the last visit a second chance, and frees the others.
    private func evictAndAllocate(_ points: Int, _ frame: UInt64) -> ArenaBlock? {
        precondition(points >= 1, "An allocation needs points, got \(points)")
        RenderSignpost.begin("EvictAndAllocate")
        defer { RenderSignpost.end("EvictAndAllocate") }
        let protectedAfter = frame > Self.framesInFlight ? frame - Self.framesInFlight : 0
        let target = Int(Double(arena.byteBudget) * (1 - Self.evictionMargin))
        // Two rounds visit each stroke twice: once to clear its mark, once to free it.
        let steps = 2 * residentSlots.count
        for _ in 0..<steps where !residentSlots.isEmpty {
            clockHand %= residentSlots.count
            let slot = residentSlots[clockHand]
            if infos[slot].lastDrawnFrame >= protectedAfter {
                clockHand += 1
            } else if infos[slot].isReferenced {
                infos[slot].isReferenced = false
                clockHand += 1
            } else {
                evict(slot)
                if arena.usedBytes <= target, let result = arena.allocate(points: points) {
                    return result
                }
            }
        }
        let result = arena.allocate(points: points)
        assert(
            result != nil
                || residentSlots.allSatisfy { infos[$0].lastDrawnFrame >= protectedAfter },
            "Eviction stopped while a stroke could still be freed"
        )
        return result
    }

    /// Frees the block of a stroke and removes it from the resident list. The last resident
    /// stroke takes its place, so the hand visits it next.
    private func evict(_ slot: Int) {
        guard let block = infos[slot].block else {
            preconditionFailure("Slot \(slot) has no block")
        }
        let index = infos[slot].residentIndex
        precondition(residentSlots.indices.contains(index), "Slot \(slot) is not resident")
        arena.free(block)
        infos[slot].block = nil
        infos[slot].residentIndex = -1
        let moved = residentSlots.removeLast()
        if moved != slot {
            residentSlots[index] = moved
            infos[moved].residentIndex = index
        }
        assert(residentSlots.count <= infos.count, "More resident strokes than strokes")
    }

    /// Returns the bend of block `block` of the stroke in `slot`, and measures it at the first
    /// call (`BlockSpacing.bend(of:block:)`).
    ///
    /// - Precondition: The slot and the block exist.
    func bend(slot: Int, block: Int) -> Float {
        precondition(infos.indices.contains(slot), "Stroke slot \(slot) does not exist")
        precondition(block >= 0 && block < infos[slot].blockCount, "Block \(block) is unknown")
        let index = infos[slot].firstBlock + block
        if !blockBends[index].isNaN { return blockBends[index] }
        let bend = BlockSpacing.bend(of: points[slot], block: block)
        blockBends[index] = bend
        return bend
    }

    /// Returns the block spacings of a stroke.
    ///
    /// - Precondition: `info` is the draw data of a stroke of this store.
    func spacings(of info: DrawInfo) -> ArraySlice<BlockSpacing> {
        precondition(info.firstBlock + info.blockCount <= blockSpacings.count, "Unknown blocks")
        precondition(info.blockCount >= 1, "A stroke has one block at least")
        return blockSpacings[info.firstBlock..<(info.firstBlock + info.blockCount)]
    }
}
