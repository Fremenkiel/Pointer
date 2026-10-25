import Geometry
import Metal
import Model

extension FrameRenderer {
    /// The clear color of a pass into a drawable: the canvas color (D-106).
    ///
    /// - Precondition: Each channel of `background` is from 0 to 1.
    static func clearColor(_ background: SIMD3<Float>) -> MTLClearColor {
        precondition(
            background.min() >= 0 && background.max() <= 1,
            "The background is in sRGB from 0 to 1, got \(background)"
        )
        let color = MTLClearColor(
            red: Double(background.x),
            green: Double(background.y),
            blue: Double(background.z),
            alpha: 1
        )
        return color
    }

    /// Renders strokes, text boxes, and cards into an image with the same pipelines as the screen.
    /// Only the tests use it.
    ///
    /// - Precondition: The view size times the scale gives at least one pixel.
    /// - Throws: `RenderingError` if a Metal object fails.
    /// - Returns: The image of the view: white ink and text on the background of the
    ///   configuration.
    func renderImage(
        of strokes: [Stroke],
        textBoxes: [TextBox] = [],
        cards: [Card] = [],
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
        let text = try encodeText(
            textBoxes,
            cards: cards,
            target: target,
            commandBuffer: commandBuffer
        )
        encodeCopy(coverage: coverage, output: output, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        withExtendedLifetime((encoder, text)) {}
        return RenderedImage(width: width, height: height, pixels: readPixels(of: output))
    }

    /// Encodes the resolve of the preview targets and the copy of the image into a new shared
    /// buffer of the image size.
    ///
    /// - Precondition: The image lies inside the targets.
    /// - Throws: `RenderingError.resourceUnavailable` if Metal gives no buffer or no encoder.
    /// - Returns: The buffer that holds the image after the GPU completes `commandBuffer`.
    func encodeReadback(
        of preview: PreviewRenderer,
        image: MTLRegion,
        commandBuffer: any MTLCommandBuffer
    ) throws(RenderingError) -> any MTLBuffer {
        let size = image.size
        precondition(
            image.origin.x + size.width <= PreviewRenderer.side
                && image.origin.y + size.height <= PreviewRenderer.side,
            "The image lies inside the targets, got \(image)"
        )
        guard
            let readback = resources.device.makeBuffer(
                length: size.width * size.height,
                options: .storageModeShared
            )
        else { throw .resourceUnavailable("preview readback buffer") }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = preview.resolved
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let resolve = commandBuffer.makeRenderCommandEncoder(descriptor: pass),
            let blit = Self.resolve(resolve, renderer: preview, commandBuffer: commandBuffer)
        else { throw .resourceUnavailable("preview resolve") }
        blit.copy(
            from: preview.resolved,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: image.origin,
            sourceSize: size,
            to: readback,
            destinationOffset: 0,
            destinationBytesPerRow: size.width,
            destinationBytesPerImage: size.width * size.height
        )
        blit.endEncoding()
        return readback
    }

    /// Draws all strokes in one pass with a store of their own. The encoder must live until the
    /// GPU completes, because it owns the arena. The pass clears the target if `clear` is set.
    func encodeStrokes(
        _ strokes: [Stroke],
        target: InkTarget,
        commandBuffer: any MTLCommandBuffer,
        clear: Bool = true
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
        // A stroke writes at most one draw entry per block.
        let entries = strokes.reduce(0) { $0 + DetailRuns.blockCount(pointCount: $1.points.count) }
        let ring = try DrawListRing(device: resources.device, capacity: max(1, entries))
        let encoder = InkEncoder(resources: resources, store: store, ring: ring)
        let context = FrameContext(commandBuffer: commandBuffer, frame: 1)
        encoder.beginFrame(context)
        let options = InkPassOptions(clear: clear, instanceBudget: .max)
        let cursor = encoder.encodePass(
            context,
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

    /// Draws the text boxes and cards in one pass with stores, an atlas, and a glyph buffer of
    /// their own. With a `region`, only the items that touch it draw. The encoder must live
    /// until the GPU completes, because it owns the buffer.
    func encodeText(
        _ boxes: [TextBox],
        cards: [Card],
        target: InkTarget,
        commandBuffer: any MTLCommandBuffer,
        region: Rect? = nil
    ) throws(RenderingError) -> TextEncoder {
        precondition(boxes.count <= Limits.maxNodesPerCanvas, "Too many text boxes")
        let store = TextStore()
        for box in boxes {
            store.add(box)
        }
        let cardStore = CardStore()
        for card in cards {
            cardStore.add(card)
        }
        assert(cardStore.count == Set(cards.map(\.id)).count, "Each card is in the store once")
        // A card writes a border quad, a preview quad, and its title glyphs.
        let titles = cardStore.entries.values.reduce(0) { $0 + 2 + ($1.layout?.glyphs.count ?? 0) }
        let glyphs = store.entries.values.reduce(titles) { $0 + $1.layout.glyphs.count }
        let encoder = TextEncoder(
            resources: resources,
            store: store,
            cards: cardStore,
            atlas: GlyphAtlas(
                device: resources.device,
                byteBudget: configuration.glyphAtlasByteBudget
            ),
            ring: try GlyphRing(device: resources.device, capacity: max(1, glyphs)),
            borderCoverage: configuration.cardBorderCoverage,
            fillCoverage: configuration.cardFillCoverage
        )
        encoder.beginFrame()
        let ids = Self.greenItems(cards: cardStore, boxes: store, order: (cards, boxes), in: region)
        let context = FrameContext(commandBuffer: commandBuffer, frame: 1)
        let cursor = encoder.encodePass(
            context,
            target: target,
            ids: ids,
            cursor: 0,
            options: TextEncoder.Options()
        )
        guard cursor == ids.count else {
            throw .resourceUnavailable("glyph buffer for \(ids.count) text boxes and cards")
        }
        return encoder
    }

    /// Returns the cards and the text boxes to draw: all of them in the given order, or with a
    /// `region`, the ones whose bounds touch it.
    private static func greenItems(
        cards: CardStore,
        boxes: TextStore,
        order: ([Card], [TextBox]),
        in region: Rect?
    ) -> [GreenItem] {
        var ids = order.0.map { GreenItem.card($0.id) } + order.1.map { .textBox($0.id) }
        guard let region else { return ids }
        ids.removeAll(keepingCapacity: true)
        cards.grid.forEachItem(touching: region) { ids.append(.card($0)) }
        boxes.grid.forEachItem(touching: region) { ids.append(.textBox($0)) }
        return ids
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
        pass.colorAttachments[0].clearColor = Self.clearColor(configuration.background)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let size = SIMD2(Float(coverage.width), Float(coverage.height))
        let uniforms = CompositeUniforms(
            scale: SIMD2(1, 1),
            offset: .zero,
            textureSize: size,
            background: SIMD4(configuration.background, 1)
        )
        encoder.setRenderPipelineState(resources.compositePipeline)
        encoder.setFragmentTexture(coverage, index: 0)
        encoder.setFragmentValue(uniforms, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
