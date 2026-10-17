import Geometry
import Metal
import Model

extension FrameRenderer {
    /// Renders strokes into an image with the same pipelines as the screen. Tests and the
    /// handoff comparison use it.
    ///
    /// - Precondition: The view size times the scale gives at least one pixel.
    /// - Throws: `RenderingError` if a Metal object fails.
    /// - Returns: The image of the view, black with white ink.
    func renderImage(
        of strokes: [Stroke],
        camera: Camera,
        viewSize: Size,
        displayScale: Double
    ) throws(RenderingError) -> RenderedImage {
        let width = Int((viewSize.width * displayScale).rounded())
        let height = Int((viewSize.height * displayScale).rounded())
        precondition(width > 0 && height > 0, "Image of \(width) x \(height) pixels is empty")
        let coverage = try resources.makeTarget(
            width: width,
            height: height,
            format: InkResources.committedFormat
        )
        let output = try resources.makeTarget(
            width: width,
            height: height,
            format: InkResources.drawableFormat,
            isReadable: true
        )
        guard let commandBuffer = resources.queue.makeCommandBuffer() else {
            throw .resourceUnavailable("command buffer")
        }
        let target = InkTarget(texture: coverage, camera: camera, displayScale: displayScale)
        let encoder = try encodeStrokes(strokes, target: target, commandBuffer: commandBuffer)
        encodeCopy(coverage: coverage, output: output, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        withExtendedLifetime(encoder) {}
        return RenderedImage(width: width, height: height, pixels: readPixels(of: output))
    }

    /// Draws all strokes in one pass with a store of their own. The encoder must live until the
    /// GPU completes, because it owns the arena.
    private func encodeStrokes(
        _ strokes: [Stroke],
        target: InkTarget,
        commandBuffer: any MTLCommandBuffer
    ) throws(RenderingError) -> InkEncoder {
        let points = strokes.reduce(0) { $0 + $1.points.count }
        // A block holds at most twice its points, and each size class can leave one partial slab.
        let slabs = (points * 2) / SlabAllocator.slabPoints + SlabAllocator.classCount + 1
        let arena = try PointArena(
            device: resources.device,
            initialSlabs: slabs,
            byteBudget: slabs * PointArena.bytesPerSlab
        )
        let store = StrokeStore(arena: arena)
        let slots = strokes.map { store.add($0) }
        assert(store.count == Set(strokes.map(\.id)).count, "Each stroke has one slot")
        let ring = try DrawListRing(device: resources.device, capacity: max(1, strokes.count))
        let encoder = InkEncoder(resources: resources, store: store, ring: ring)
        ring.beginFrame(commandBuffer)
        let options = InkPassOptions(clear: true, instanceBudget: .max, frame: 1)
        let cursor = encoder.encodePass(
            commandBuffer,
            target: target,
            slots: slots,
            cursor: 0,
            options: options
        )
        guard cursor == slots.count else {
            throw .resourceUnavailable("draw list for \(slots.count) strokes")
        }
        return encoder
    }

    private func encodeCopy(
        coverage: any MTLTexture,
        output: any MTLTexture,
        commandBuffer: any MTLCommandBuffer
    ) {
        precondition(coverage.width == output.width, "Copy textures differ in width")
        precondition(coverage.height == output.height, "Copy textures differ in height")
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let size = SIMD2(Float(coverage.width), Float(coverage.height))
        let uniforms = CompositeUniforms(scale: SIMD2(1, 1), offset: .zero, textureSize: size)
        encoder.setRenderPipelineState(resources.compositePipeline)
        encoder.setFragmentTexture(coverage, index: 0)
        encoder.setFragmentValue(uniforms, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
