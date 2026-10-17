import Geometry
import Model
import os

/// The strokes that the renderer knows, their arena blocks, and their spatial index.
///
/// The renderer keeps its own GPU state and receives only new strokes (data-model.md 8). A
/// stroke can leave the arena when the arena is at its budget. The next draw then copies its
/// points in again from `InkPoints`.
@MainActor
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
        let meanSpacing: Double
        let maxSpacing: Double
        var block: ArenaBlock?
        var lastDrawnFrame: UInt64 = 0
    }

    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Rendering")
    private let signposter = OSSignposter(subsystem: "dk.saarikivi.pointer", category: "Rendering")
    private(set) var infos: [DrawInfo] = []
    /// The strokes by slot. Only an upload into the arena reads them.
    private var strokes: [Stroke] = []
    private var slotByID: [StrokeID: Int] = [:]
    private(set) var grid = SpatialGrid<Int>(cellSize: gridCellSize)
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
        let spacing = Self.spacing(of: stroke.points)
        let slot = infos.count
        let info = DrawInfo(
            origin: stroke.origin,
            radius: stroke.width / 2,
            pointCount: stroke.points.count,
            meanSpacing: spacing.mean,
            maxSpacing: spacing.max
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
        assert(block.capacity >= info.pointCount, "Block \(block) is too small for slot \(slot)")
        return infos[slot]
    }

    private func evictAndAllocate(_ points: Int, _ frame: UInt64) -> ArenaBlock? {
        precondition(points >= 1, "An allocation needs points, got \(points)")
        let state = signposter.beginInterval("EvictAndAllocate")
        defer { signposter.endInterval("EvictAndAllocate", state) }
        let protectedAfter = frame > Self.framesInFlight ? frame - Self.framesInFlight : 0
        var candidates = infos.indices.filter {
            infos[$0].block != nil && infos[$0].lastDrawnFrame < protectedAfter
        }
        candidates.sort { infos[$0].lastDrawnFrame < infos[$1].lastDrawnFrame }
        let target = Int(Double(arena.byteBudget) * (1 - Self.evictionMargin))
        for slot in candidates {
            guard let block = infos[slot].block else { continue }
            arena.free(block)
            infos[slot].block = nil
            if arena.usedBytes <= target, let result = arena.allocate(points: points) {
                return result
            }
        }
        let result = arena.allocate(points: points)
        assert(
            result != nil || candidates.allSatisfy { infos[$0].block == nil },
            "Eviction stopped early"
        )
        return result
    }

    /// Returns the mean and the largest distance between neighbor control points.
    static func spacing(of points: InkPoints) -> (mean: Double, max: Double) {
        let values = points.values
        precondition(values.count >= 2, "A stroke has 2 points at least")
        var total = 0.0
        var largest = 0.0
        for index in 1..<values.count {
            let dx = Double(values[index].x - values[index - 1].x)
            let dy = Double(values[index].y - values[index - 1].y)
            let length = (dx * dx + dy * dy).squareRoot()
            total += length
            largest = max(largest, length)
        }
        // Equal segments can give a mean one rounding step above the largest spacing.
        let mean = min(total / Double(values.count - 1), largest)
        assert(mean >= 0 && mean.isFinite, "The mean spacing \(mean) is invalid")
        return (mean, largest)
    }
}
