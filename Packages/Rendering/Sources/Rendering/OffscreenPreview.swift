import Geometry
import Metal
import Model

/// The parts that the offscreen previews of `PreviewMaker` use, and nothing more (review M9
/// section 3.3, item 4, the M10 plan task 3.4). A whole `FrameRenderer` held an unused arena of
/// 16 MB, a second glyph table, and text lists, and each preview built a new atlas, glyph ring,
/// and text encoder. Here one atlas, one ring of one buffer, and one encoder with its stores
/// serve all previews.
final class OffscreenPreview {
    /// The glyph quads of the first ring. A larger preview puts a larger ring in place.
    static let initialGlyphCapacity = 4_096

    let resources: InkResources
    let configuration: RendererConfiguration
    /// The coverage and resolve targets of the previews.
    let targets: PreviewRenderer
    let texts = TextStore()
    let cards = CardStore()
    /// The encoder of the text. A preview that needs a larger glyph ring makes a new one. The
    /// ring of an encoder is a constant, because a variable costs an exclusivity check at each
    /// read in the text pass of the screen.
    private(set) var text: TextEncoder
    private let atlas: GlyphAtlas
    /// The number of the last preview. The atlas drops the pages of old previews first.
    private var frame: UInt64 = 0

    /// Makes the parts on the system GPU.
    ///
    /// - Throws: `RenderingError` if the device has no GPU or a Metal object fails.
    init(configuration: RendererConfiguration) throws(RenderingError) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw .noDevice }
        resources = try InkResources.shared(device: device)
        self.configuration = configuration
        targets = try PreviewRenderer(resources: resources)
        let atlas = GlyphAtlas(device: device, byteBudget: configuration.glyphAtlasByteBudget)
        self.atlas = atlas
        text = try Self.encoder(
            resources: resources,
            configuration: configuration,
            stores: (texts, cards),
            atlas: atlas,
            capacity: Self.initialGlyphCapacity
        )
    }

    /// Makes a text encoder with a glyph ring of one buffer of `capacity` quads.
    ///
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make the buffer.
    private static func encoder(
        resources: InkResources,
        configuration: RendererConfiguration,
        stores: (TextStore, CardStore),
        atlas: GlyphAtlas,
        capacity: Int
    ) throws(RenderingError) -> TextEncoder {
        let ring = try GlyphRing(device: resources.device, capacity: capacity, bufferCount: 1)
        return TextEncoder(
            resources: resources,
            store: stores.0,
            cards: stores.1,
            atlas: atlas,
            ring: ring,
            borderCoverage: configuration.cardBorderCoverage,
            fillCoverage: configuration.cardFillCoverage
        )
    }

    /// Renders the preview of the items of `content` that touch the region of `placement`.
    /// Cards show their frames and titles without previews. The strokes draw in passes whose
    /// points fit `previewArenaByteBudget`. It blocks until the GPU completes (the M6 plan task
    /// 3.3, item 6).
    ///
    /// - Precondition: The content keeps the node limit.
    /// - Throws: `RenderingError` if a Metal object fails.
    /// - Returns: The gray image of the placement.
    func render(
        _ content: CanvasContent,
        placement: PreviewRenderer.Placement
    ) throws(RenderingError) -> PreviewImage {
        let nodes = content.cards.count + content.textBoxes.count
        precondition(nodes <= Limits.maxNodesPerCanvas, "Too many nodes: \(nodes)")
        frame += 1
        let region = placement.region
        let target = InkTarget(texture: targets.coverage, camera: placement.camera, displayScale: 1)
        let strokes = content.strokes.values.filter { $0.bounds.intersects(region) }
        try encodeStrokePasses(strokes, target: target)
        guard let commandBuffer = resources.queue.makeCommandBuffer() else {
            throw .resourceUnavailable("command buffer")
        }
        try encodeText(of: content, target: target, region: region, commandBuffer: commandBuffer)
        let size = placement.image.size
        let readback = try FrameRenderer.encodeReadback(
            of: targets,
            image: placement.image,
            commandBuffer: commandBuffer,
            resources: resources
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        try Self.checkCompleted(commandBuffer)
        let image = PreviewRenderer.readImage(of: readback, width: size.width, height: size.height)
        guard let image else { throw .resourceUnavailable("preview readback") }
        return image
    }

    /// Draws `strokes` in passes of one command buffer each, so that the arena of a pass keeps
    /// `previewArenaByteBudget`. The first pass clears the target, also without a stroke. Each
    /// pass waits for the GPU, and its arena goes before the next one comes.
    private func encodeStrokePasses(
        _ strokes: [Stroke],
        target: InkTarget
    ) throws(RenderingError) {
        let passes = PreviewPasses.split(strokes, byteBudget: configuration.previewArenaByteBudget)
        precondition(!passes.isEmpty, "The first pass clears the target")
        for (index, pass) in passes.enumerated() {
            guard let commandBuffer = resources.queue.makeCommandBuffer() else {
                throw .resourceUnavailable("command buffer")
            }
            let ink = try FrameRenderer.encodeStrokes(
                pass,
                target: target,
                commandBuffer: commandBuffer,
                clear: index == 0,
                resources: resources
            )
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            withExtendedLifetime(ink) {}
            try Self.checkCompleted(commandBuffer)
        }
        assert(passes.joined().count == strokes.count, "Each stroke draws in one pass")
    }

    /// Fills the stores with the text boxes and the cards that can touch `region` and encodes
    /// the ones that touch it into `commandBuffer`. The title of a card lies above and beside
    /// its frame, as in the grid of the screen.
    private func encodeText(
        of content: CanvasContent,
        target: InkTarget,
        region: Rect,
        commandBuffer: any MTLCommandBuffer
    ) throws(RenderingError) {
        texts.removeAll()
        cards.removeAll()
        for box in content.textBoxes.values where FrameRenderer.mayTouch(box, region) {
            texts.add(box)
        }
        let cardRegion = region.expanded(by: Limits.cardTitleReach)
        for card in content.cards.values where card.frame.intersects(cardRegion) {
            cards.add(card)
        }
        let ids = FrameRenderer.greenItems(cards: cards, boxes: texts, order: ([], []), in: region)
        try reserveGlyphs(for: ids)
        text.beginFrame()
        let context = FrameContext(commandBuffer: commandBuffer, frame: frame)
        let cursor = text.encodePass(
            context,
            target: target,
            ids: ids,
            cursor: 0,
            options: TextEncoder.Options()
        )
        guard cursor == ids.count else {
            throw .resourceUnavailable("glyph buffer for \(ids.count) text boxes and cards")
        }
    }

    /// Makes an encoder with a larger ring if the items of `ids` need more glyph quads than the
    /// ring holds.
    private func reserveGlyphs(for ids: [GreenItem]) throws(RenderingError) {
        let glyphs = ids.reduce(0) { $0 + (text.quadCount(of: $1) ?? 0) }
        guard glyphs > text.ring.capacity else { return }
        text = try Self.encoder(
            resources: resources,
            configuration: configuration,
            stores: (texts, cards),
            atlas: atlas,
            capacity: glyphs
        )
    }

    /// Throws if the GPU did not complete `commandBuffer`, for example because the app went to
    /// the background. The readback buffer then holds no image, and a black preview must not
    /// reach the cache (review after M9).
    private static func checkCompleted(
        _ commandBuffer: any MTLCommandBuffer
    ) throws(RenderingError) {
        try FrameRenderer.checkCompleted(status: commandBuffer.status, error: commandBuffer.error)
    }
}
