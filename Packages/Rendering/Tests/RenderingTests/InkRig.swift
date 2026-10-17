import Geometry
import Metal
import Model

@testable import Rendering

/// The internal ink types of the renderer over one set of strokes, with an arena that holds all
/// points. Performance tests use it to time one content pass on the GPU.
@MainActor
final class InkRig {
    let resources: InkResources
    let store: StrokeStore
    let encoder: InkEncoder

    /// Makes the rig and adds all strokes.
    ///
    /// - Throws: `RenderingError` if the device has no GPU or a Metal object fails.
    init(strokes: [Stroke]) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderingError.noDevice }
        resources = try InkResources(device: device)
        let points = strokes.reduce(0) { $0 + $1.points.count }
        // A block holds at most twice its points, and each size class can leave one partial slab.
        let slabs = (points * 2) / SlabAllocator.slabPoints + SlabAllocator.classCount + 1
        let arena = try PointArena(
            device: device,
            initialSlabs: slabs,
            byteBudget: slabs * PointArena.bytesPerSlab
        )
        store = StrokeStore(arena: arena)
        for stroke in strokes {
            store.add(stroke)
        }
        let ring = try DrawListRing(device: device, capacity: max(1, strokes.count))
        encoder = InkEncoder(resources: resources, store: store, ring: ring)
        assert(store.count == strokes.count, "Each stroke has its own slot")
    }

    /// Returns the slots of the strokes that touch the target.
    func visibleSlots(of target: InkTarget) -> [Int] {
        var slots: [Int] = []
        store.grid.forEachItem(touching: target.canvasRect) { slots.append($0) }
        return slots
    }

    /// Encodes the slots into the target in one clear pass and commits it. The caller waits for
    /// the GPU, so that several passes can run back to back.
    ///
    /// - Returns: The committed command buffer of the pass.
    func commitPass(slots: [Int], target: InkTarget) -> any MTLCommandBuffer {
        guard let commandBuffer = resources.queue.makeCommandBuffer() else {
            preconditionFailure("Metal gave no command buffer")
        }
        encoder.ring.beginFrame(commandBuffer)
        let options = InkPassOptions(clear: true, instanceBudget: .max, frame: 1)
        let cursor = encoder.encodePass(
            commandBuffer,
            target: target,
            slots: slots,
            cursor: 0,
            options: options
        )
        precondition(cursor == slots.count, "The pass drew \(cursor) of \(slots.count) strokes")
        commandBuffer.commit()
        return commandBuffer
    }

    /// Returns the draw instances of the slots at the spacing of the encoder.
    func instanceCount(slots: [Int], target: InkTarget) -> Int {
        slots.reduce(0) { total, slot in
            let info = store.infos[slot]
            let detail = LevelOfDetail(
                pointCount: info.pointCount,
                meanSpacing: info.meanSpacing,
                maxSpacing: info.maxSpacing,
                pixelsPerCanvasPoint: target.pixelsPerCanvasPoint,
                minimumPixelSpacing: encoder.minimumPixelSpacing
            )
            return total + detail.instanceCount
        }
    }
}
