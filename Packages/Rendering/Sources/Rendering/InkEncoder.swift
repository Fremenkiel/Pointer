import Geometry
import Metal
import Model
import QuartzCore

/// Encodes ink passes: one instanced draw for many strokes with vertex pulling (D-28).
final class InkEncoder {
    /// Half the width of the anti-aliased edge, in pixels. It matches the edge of the PencilKit
    /// monoline (docs/m2-plan.md section 1, fact 3).
    static let edgeHalfWidthPixels: Float = 1.06
    /// The pass reads the clock once per this number of strokes.
    static let deadlineCheckInterval = 32

    private let resources: InkResources
    private let store: StrokeStore
    let ring: DrawListRing
    /// The level-of-detail spacing of the draws. Tests change it to compare values.
    var minimumPixelSpacing = LevelOfDetail.minimumPixelSpacing

    /// Makes an encoder.
    init(resources: InkResources, store: StrokeStore, ring: DrawListRing) {
        self.resources = resources
        self.store = store
        self.ring = ring
    }

    /// Encodes the strokes of `slots` from `cursor` on until the instance budget or the draw
    /// list is full. A pass draws at least one stroke.
    ///
    /// - Precondition: `cursor` is a valid start in `slots`, and the budget is positive.
    /// - Returns: The new cursor. It equals `slots.count` when all strokes are drawn.
    func encodePass(
        _ commandBuffer: any MTLCommandBuffer,
        target: InkTarget,
        slots: [Int],
        cursor: Int,
        options: InkPassOptions
    ) -> Int {
        precondition(cursor >= 0 && cursor <= slots.count, "Cursor \(cursor) out of \(slots.count)")
        precondition(options.instanceBudget > 0, "Instance budget must be positive")
        let firstEntry = ring.used
        var position = cursor
        var instances = 0
        for slot in slots[cursor...] {
            let isFirst = position == cursor
            guard ring.remaining >= store.infos[slot].blockCount else { break }
            guard isFirst || instances < options.instanceBudget else { break }
            guard isFirst || !Self.isPastDeadline(position - cursor, options.deadline) else {
                break
            }
            instances += appendEntries(
                slot,
                target: target,
                frame: options.frame,
                firstInstance: instances
            )
            position += 1
        }
        assert(
            position > cursor || cursor == slots.count
                || ring.remaining < store.infos[slots[cursor]].blockCount,
            "A pass must advance unless the draw list is full"
        )
        let draw = InkDraw(
            entries: firstEntry..<ring.used,
            instances: instances,
            clear: options.clear
        )
        encode(draw, into: commandBuffer, target: target)
        return position
    }

    /// Writes one draw entry per level-of-detail run of a stroke.
    ///
    /// - Returns: The instances of the entries, or 0 if the arena has no room for the stroke.
    private func appendEntries(
        _ slot: Int,
        target: InkTarget,
        frame: UInt64,
        firstInstance: Int
    ) -> Int {
        guard let info = store.residentInfo(of: slot, frame: frame), let block = info.block else {
            return 0
        }
        // The subtraction runs in Double before the conversion to Float (architecture.md 5.3).
        let delta = info.origin - target.camera.center
        let origin = SIMD2(Float(delta.dx), Float(delta.dy))
        var instances = 0
        DetailRuns.forEach(
            pointCount: info.pointCount,
            spacings: store.spacings(of: info),
            pixelsPerCanvasPoint: target.pixelsPerCanvasPoint,
            minimumPixelSpacing: minimumPixelSpacing
        ) { run in
            let detail = StrokeDrawEntry.packDetail(
                stride: run.stride,
                pieces: run.pieces,
                nextOffset: run.nextOffset
            )
            ring.append(
                StrokeDrawEntry(
                    origin: origin,
                    firstPoint: UInt32(block.start + run.start),
                    pointCount: UInt32(run.end - run.start + 1),
                    firstSegment: StrokeDrawEntry.packStart(
                        start: run.start,
                        previousOffset: run.previousOffset
                    ),
                    detail: detail,
                    firstInstance: UInt32(firstInstance + instances),
                    radius: info.radius
                )
            )
            instances += run.instanceCount
        }
        assert(instances > 0, "A resident stroke draws one instance at least")
        return instances
    }

    /// Reading the clock costs time too, so the pass checks it every few strokes.
    private static func isPastDeadline(_ drawn: Int, _ deadline: TimeInterval) -> Bool {
        drawn.isMultiple(of: deadlineCheckInterval) && CACurrentMediaTime() > deadline
    }

    private func encode(
        _ draw: InkDraw,
        into commandBuffer: any MTLCommandBuffer,
        target: InkTarget
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target.texture
        pass.colorAttachments[0].loadAction = draw.clear ? .clear : .load
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            assertionFailure("Metal gave no render encoder for the ink pass")
            return
        }
        encoder.label = "Ink"
        assert(draw.instances >= 0, "Instance count \(draw.instances) is negative")
        if !draw.entries.isEmpty && draw.instances > 0 {
            encoder.setRenderPipelineState(resources.inkPipeline)
            encoder.setVertexBuffer(store.arena.buffer, offset: 0, index: 0)
            let entryOffset = draw.entries.lowerBound * MemoryLayout<StrokeDrawEntry>.stride
            encoder.setVertexBuffer(ring.buffer, offset: entryOffset, index: 1)
            let uniforms = Self.uniforms(target: target, entryCount: draw.entries.count)
            encoder.setVertexValue(uniforms, index: 2)
            encoder.setFragmentValue(uniforms, index: 2)
            encoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: draw.instances
            )
        }
        encoder.endEncoding()
    }

    private static func uniforms(target: InkTarget, entryCount: Int) -> InkUniforms {
        precondition(entryCount > 0, "An ink draw needs entries")
        let size = target.pixelSize
        assert(size.width >= 1 && size.height >= 1, "Ink target is empty")
        return InkUniforms(
            targetSize: SIMD2(Float(size.width), Float(size.height)),
            offset: SIMD2(Float(size.width / 2), Float(size.height / 2)),
            scale: Float(target.pixelsPerCanvasPoint),
            entryCount: UInt32(entryCount),
            edge: edgeHalfWidthPixels
        )
    }
}

/// One instanced draw over a range of the draw list.
private struct InkDraw {
    let entries: Range<Int>
    let instances: Int
    let clear: Bool
}
