import Geometry
import Metal
import Model
import QuartzCore

/// Encodes ink passes: one instanced draw per arena buffer for many strokes with vertex pulling
/// (D-28).
final class InkEncoder {
    /// Half the width of the anti-aliased edge, in pixels. It matches the edge of the PencilKit
    /// monoline (docs/m2-plan.md section 1, fact 3).
    static let edgeHalfWidthPixels: Float = 1.06
    /// The pass reads the clock once per this number of strokes.
    static let deadlineCheckInterval = 32

    private let resources: InkResources
    private let store: StrokeStore
    private let ring: DrawListRing
    /// The level-of-detail spacing of the draws. Tests change it to compare values.
    var minimumPixelSpacing = LevelOfDetail.minimumPixelSpacing
    /// `false` uses the pieces of before phase 3, task 3. Tests change it to compare images.
    var usesSmoothPieces = true
    /// The ink pass, made once (PERF-01, docs/m2-fix-plan.md, phase 5).
    private let inkPass: MTLRenderPassDescriptor = {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        return pass
    }()
    /// The entry lists of the passes. A pass moves them into a local value and back.
    private var buckets = EntryBuckets()

    /// Makes an encoder.
    init(resources: InkResources, store: StrokeStore, ring: DrawListRing) {
        self.resources = resources
        self.store = store
        self.ring = ring
    }

    /// Starts a frame: it waits for a free draw list and makes it the list of the frame.
    func beginFrame(_ context: FrameContext) {
        ring.beginFrame(context.commandBuffer)
    }

    /// Encodes the strokes of `slots` from `cursor` on until the instance budget or the draw
    /// list is full. A pass draws at least one stroke.
    ///
    /// - Precondition: `cursor` is a valid start in `slots`, and the budget is positive.
    /// - Returns: The new cursor. It equals `slots.count` when all strokes are drawn.
    func encodePass(
        _ context: FrameContext,
        target: InkTarget,
        slots: [Int],
        cursor: Int,
        options: InkPassOptions
    ) -> Int {
        precondition(cursor >= 0 && cursor <= slots.count, "Cursor \(cursor) out of \(slots.count)")
        precondition(options.instanceBudget > 0, "Instance budget must be positive")
        var lists = EntryBuckets()
        swap(&lists, &buckets)
        lists.reset(bufferCount: store.arena.buffers.count)
        var position = cursor
        var instances = 0
        for slot in slots[cursor...] {
            let isFirst = position == cursor
            // A build lists its strokes at its start, so it can hold a stroke removed since.
            guard !store.infos[slot].isRemoved else {
                position += 1
                continue
            }
            guard lists.entryCount + store.infos[slot].blockCount <= ring.remaining else { break }
            guard isFirst || instances < options.instanceBudget else { break }
            guard isFirst || !Self.isPastDeadline(position - cursor, options.deadline) else {
                break
            }
            instances += appendEntries(slot, target: target, frame: context.frame, into: &lists)
            position += 1
        }
        assert(
            position > cursor || cursor == slots.count
                || ring.remaining < store.infos[slots[cursor]].blockCount,
            "A pass must advance unless the draw list is full"
        )
        encode(lists, into: context.commandBuffer, target: target, options: options)
        swap(&lists, &buckets)
        return position
    }

    /// Writes one draw entry per level-of-detail run of a stroke into the list of its buffer.
    ///
    /// - Returns: The instances of the entries, or 0 if the arena has no room for the stroke.
    private func appendEntries(
        _ slot: Int,
        target: InkTarget,
        frame: UInt64,
        into lists: inout EntryBuckets
    ) -> Int {
        guard let info = store.makeResident(slot, frame: frame), let block = info.block else {
            return 0
        }
        // The upload can add an arena buffer, and the new buffer needs a list.
        lists.ensure(bufferCount: store.arena.buffers.count)
        let (bucket, offset) = store.arena.location(of: block)
        let firstInstance = lists.instanceCount(of: bucket)
        // The subtraction runs in Double before the conversion to Float (architecture.md 5.3).
        let delta = info.origin - target.camera.center
        let origin = SIMD2(Float(delta.dx), Float(delta.dy))
        var instances = 0
        DetailRuns.forEach(
            pointCount: info.pointCount,
            spacings: store.spacings(of: info),
            scale: DetailScale(
                pixelsPerCanvasPoint: target.pixelsPerCanvasPoint,
                minimum: minimumPixelSpacing,
                usesSmoothPieces: usesSmoothPieces
            ),
            bend: { store.bend(slot: slot, block: $0) },
            body: { run in
                let entry = StrokeDrawEntry(
                    run,
                    origin: origin,
                    bufferOffset: offset,
                    firstInstance: firstInstance + instances,
                    radius: info.radius
                )
                lists.append(entry, instanceCount: run.instanceCount, to: bucket)
                instances += run.instanceCount
            }
        )
        assert(instances > 0, "A resident stroke draws one instance at least")
        return instances
    }

    /// Reading the clock costs time too, so the pass checks it every few strokes.
    private static func isPastDeadline(_ drawn: Int, _ deadline: TimeInterval) -> Bool {
        drawn.isMultiple(of: deadlineCheckInterval) && CACurrentMediaTime() > deadline
    }

    /// Writes the lists into the draw list and encodes one render pass with one draw per buffer.
    private func encode(
        _ lists: EntryBuckets,
        into commandBuffer: any MTLCommandBuffer,
        target: InkTarget,
        options: InkPassOptions
    ) {
        precondition(!options.clearsScissor || options.scissor != nil, "A clear needs a scissor")
        let pass = inkPass
        pass.colorAttachments[0].texture = target.texture
        pass.colorAttachments[0].loadAction = options.clear ? .clear : .load
        let made = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        // The descriptor lives on, so it must not hold the texture after the pass.
        pass.colorAttachments[0].texture = nil
        guard let encoder = made else {
            assertionFailure("Metal gave no render encoder for the ink pass")
            return
        }
        #if DEBUG
            // A label costs two allocations per pass and helps only in a GPU capture.
            encoder.label = "Ink"
        #endif
        if let scissor = options.scissor {
            encoder.setScissorRect(scissor)
        }
        if options.clearsScissor {
            // The load action clears the whole texture, so a triangle clears the rectangle.
            encoder.setRenderPipelineState(resources.clearPipeline)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.setRenderPipelineState(resources.inkPipeline)
        for (index, bucket) in lists.lists.enumerated() where !bucket.isEmpty {
            let firstEntry = ring.used
            ring.append(contentsOf: bucket)
            assert(lists.instanceCount(of: index) > 0, "A list with entries draws instances")
            encoder.setVertexBuffer(store.arena.buffers[index], offset: 0, index: 0)
            let entryOffset = firstEntry * MemoryLayout<StrokeDrawEntry>.stride
            encoder.setVertexBuffer(ring.buffer, offset: entryOffset, index: 1)
            let uniforms = Self.uniforms(target: target, entryCount: bucket.count)
            encoder.setVertexValue(uniforms, index: 2)
            encoder.setFragmentValue(uniforms, index: 2)
            encoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: lists.instanceCount(of: index)
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
