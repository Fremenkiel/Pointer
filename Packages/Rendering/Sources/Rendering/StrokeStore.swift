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
    /// The removed strokes whose blocks a frame in flight can still read, in frame order.
    private var removals: [(slot: Int, frame: UInt64)] = []
    /// The slots that a new stroke can take, after their removal is complete.
    private var freeSlots: [Int] = []
    let arena: PointArena

    /// Makes an empty store.
    init(arena: PointArena) {
        // The arrays grow with the canvas. A reserve for the stroke limit took about 40 MB for
        // every canvas (docs/m2-fix-plan.md, phase 4, task 5).
        self.arena = arena
    }

    /// The number of strokes, without the removed ones.
    var count: Int { slotByID.count }

    /// Adds a stroke and returns its slot. A stroke that the store holds keeps its slot.
    ///
    /// - Precondition: The store holds fewer than `Limits.maxStrokesPerCanvas` strokes.
    @discardableResult  // The handoff needs the slot. The load path does not.
    func add(_ stroke: Stroke) -> Int {
        if let slot = slotByID[stroke.id] { return slot }
        precondition(count < Limits.maxStrokesPerCanvas, "The renderer holds the stroke limit")
        let reused = freeSlots.popLast()
        let slot = reused ?? infos.count
        let blocks = storeSpacings(of: stroke.points, reusing: reused.map { infos[$0] })
        let info = DrawInfo(
            origin: stroke.origin,
            radius: stroke.width / 2,
            pointCount: stroke.points.count,
            firstBlock: blocks.lowerBound,
            blockCount: blocks.count
        )
        if reused == nil {
            infos.append(info)
            points.append(stroke.points)
        } else {
            infos[slot] = info
            points[slot] = stroke.points
        }
        slotByID[stroke.id] = slot
        grid.insert(slot, bounds: stroke.bounds)
        assert(slotByID.count == grid.count && points.count == infos.count, "Store arrays disagree")
        return slot
    }

    /// Writes the block spacings of a stroke. A reused slot keeps its old range if the new
    /// spacings fit into it, so a canvas that erases and draws does not grow the list.
    ///
    /// - Returns: The range of the spacings in `blockSpacings`.
    private func storeSpacings(of strokePoints: InkPoints, reusing old: DrawInfo?) -> Range<Int> {
        let first = blockSpacings.count
        BlockSpacing.append(of: strokePoints, to: &blockSpacings)
        let count = blockSpacings.count - first
        guard let old, count <= old.blockCount else {
            blockBends.append(contentsOf: repeatElement(.nan, count: count))
            return first..<(first + count)
        }
        let range = old.firstBlock..<(old.firstBlock + count)
        // A copy in place: a slice of the same array would make Swift copy the whole array.
        for offset in 0..<count {
            blockSpacings[range.lowerBound + offset] = blockSpacings[first + offset]
        }
        blockSpacings.removeLast(count)
        for index in range { blockBends[index] = .nan }
        assert(blockSpacings.count == first, "The reused range left new spacings behind")
        return range
    }

    /// Returns the bounds of a stroke, or `nil` if the store does not hold it.
    func bounds(of id: StrokeID) -> Rect? {
        guard let slot = slotByID[id] else { return nil }
        let bounds = grid.bounds(of: slot)
        assert(bounds != nil, "Stroke slot \(slot) is not in the grid")
        return bounds
    }

    /// Removes a stroke. Its slot leaves the grid at once. Its arena block stays until no frame
    /// in flight can read it, and `releaseRemovals(at:)` then frees the slot for a new stroke.
    ///
    /// - Precondition: `frame` is the current frame or later than earlier removals.
    /// - Returns: `false` if the store holds no stroke with the ID.
    @discardableResult  // A caller can remove a stroke that the renderer never got.
    func remove(_ id: StrokeID, frame: UInt64) -> Bool {
        precondition(removals.last.map { $0.frame <= frame } ?? true, "Removals out of order")
        guard let slot = slotByID.removeValue(forKey: id) else { return false }
        grid.remove(slot)
        infos[slot].isRemoved = true
        removals.append((slot, frame))
        assert(slotByID.count == grid.count, "The grid still holds a removed stroke")
        return true
    }

    /// Frees the blocks and the slots of the strokes removed `framesInFlight` frames before
    /// `frame` or earlier. The frame renderer calls it at the start of each frame.
    func releaseRemovals(at frame: UInt64) {
        let released = removals.prefix { $0.frame + Self.framesInFlight <= frame }.count
        guard released > 0 else { return }
        for (slot, _) in removals.prefix(released) {
            if infos[slot].block != nil { evict(slot) }
            freeSlots.append(slot)
        }
        removals.removeFirst(released)
        assert(freeSlots.count + removals.count + count == infos.count, "A slot got lost")
    }

    /// Makes a stroke ready to draw in frame `frame`, and returns its draw data with its arena
    /// block. It marks the stroke as drawn in that frame, copies its points into the arena if
    /// they are not there, and evicts other strokes if the arena is full.
    ///
    /// - Returns: `nil` if the arena has no room even after eviction. The caller skips the stroke.
    func makeResident(_ slot: Int, frame: UInt64) -> DrawInfo? {
        precondition(infos.indices.contains(slot), "Stroke slot \(slot) does not exist")
        precondition(!infos[slot].isRemoved, "Stroke slot \(slot) is removed")
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

    /// Returns the points of the stroke in `slot`.
    ///
    /// - Precondition: The slot exists.
    func points(of slot: Int) -> InkPoints {
        precondition(points.indices.contains(slot), "Stroke slot \(slot) does not exist")
        return points[slot]
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
