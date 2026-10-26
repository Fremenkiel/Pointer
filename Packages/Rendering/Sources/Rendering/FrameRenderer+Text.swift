import Metal

/// The text encoder of the screen, with the stored glyph runs (architecture.md 5.4.1, D-188).
extension FrameRenderer {
    /// Makes the text encoder of the screen. With a run budget, the encoder makes the stored
    /// runs at the first large layout, and the atlas then keeps its pages in heaps.
    ///
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make a buffer.
    static func makeTextEncoder(
        _ resources: InkResources,
        _ configuration: RendererConfiguration,
        stores: (TextStore, CardStore)
    ) throws(RenderingError) -> TextEncoder {
        precondition(configuration.glyphCapacity > 0, "A frame holds glyph quads")
        let device = resources.device
        let atlas = GlyphAtlas(device: device, byteBudget: configuration.glyphAtlasByteBudget)
        let budget = configuration.glyphRunByteBudget
        return TextEncoder(
            resources: resources,
            store: stores.0,
            cards: stores.1,
            atlas: atlas,
            ring: try GlyphRing(device: device, capacity: configuration.glyphCapacity),
            storedLimits: budget > 0 ? (configuration.storedGlyphCapacity, budget) : nil,
            borderCoverage: configuration.cardBorderCoverage,
            fillCoverage: configuration.cardFillCoverage
        )
    }
}
