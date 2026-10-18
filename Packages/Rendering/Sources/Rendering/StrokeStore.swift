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
    struct DrawInfo {
        let origin: Point
        let radius: Float
        let pointCount: Int
        /// The index of the first block spacing of the stroke in `blockSpacings`.
        let firstBlock: Int
        /// The number of blocks of the stroke (`DetailRuns`).
        let blockCount: Int
        var block: ArenaBlock?
        var lastDrawnFrame: UInt64 = 0
        /// `true` after a draw. The clock sweep clears it once before it evicts the stroke.
        var isReferenced = false
        /// The index of the stroke in `residentSlots`, or -1 if the stroke has no block.
        var residentIndex = -1
    }

    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Rendering")
    private let signposter = OSSignposter(subsystem: "dk.saarikivi.pointer", category: "Rendering")
    private(set) var infos: [DrawInfo] = []
    /// The strokes by slot. Only an upload into the arena reads them.
    private var strokes: [Stroke] = []
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
        self.arena = arena
        infos.reserveCapacity(Limits.maxStrokesPerCanvas)
        strokes.reserveCapacity(Limits.maxStrokesPerCanvas)
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
        strokes.append(stroke)
        slotByID[stroke.id] = slot
        grid.insert(slot, bounds: stroke.bounds)
        assert(infos.count == grid.count && strokes.count == infos.count, "Store arrays disagree")
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
        let points = strokes[slot].points
        guard
            let block = arena.allocate(points: points.count)
                ?? evictAndAllocate(points.count, frame)
        else {
            logger.error("Point arena is full. A stroke of \(points.count) points is not drawn.")
            return nil
        }
        arena.write(points, to: block)
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
        let state = signposter.beginInterval("EvictAndAllocate")
        defer { signposter.endInterval("EvictAndAllocate", state) }
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
        let bend = BlockSpacing.bend(of: strokes[slot].points, block: block)
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
