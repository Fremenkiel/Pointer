import Geometry
import Metal
import Model
import QuartzCore

/// Encodes text passes: one glyph quad per glyph from the atlas into the text channel of a
/// committed texture (architecture.md 5.4, D-29, D-82). A card adds a border quad and the glyphs
/// of its title to the same pass (architecture.md 5.5, D-96).
final class TextEncoder {
    /// The options of one text pass.
    struct Options {
        /// The pixel rectangle that the pass draws into, or `nil` for the whole texture.
        var scissor: MTLScissorRect?
        /// `true` sets the text coverage of `scissor` to zero before the draw.
        var clearsScissor = false
        /// The pass stops after this `CACurrentMediaTime()` value, after its first box, as the
        /// ink of a build does (task 2.4 of docs/m5-plan.md).
        var deadline: TimeInterval = .infinity
        /// `false` draws cards without their previews and asks for none, for the render of a
        /// preview (architecture.md 5.5).
        var drawsPreviews = true
    }

    /// The pass reads the clock once per this number of boxes.
    static let deadlineCheckInterval = 8

    /// The glyph quads of one atlas page in the buffer of the frame.
    struct Run {
        let page: Int
        let first: Int
        var count: Int
    }

    /// The first capacity of the run list. It grows once to the most runs of a pass.
    private static let initialRunCapacity = 64

    let resources: InkResources
    private let store: TextStore
    /// The cards of the canvas, for the cards in the list of a pass (D-96).
    let cards: CardStore
    /// The coverage of a card border (D-96).
    let borderCoverage: Float
    /// The border quads of the current pass. They go into the glyph buffer as one run at the end
    /// of the pass, so that a pass makes one border draw. Reused (PERF-01).
    var borderQuads: [GlyphInstance] = []
    /// The run of the border quads of the current pass in the glyph buffer, or `nil`.
    var borderRun: (first: Int, count: Int)?
    /// The card previews, or `nil` before the first card (D-97).
    var previews: PreviewAtlas?
    /// The preview quads of the current pass, written as one run like `borderQuads`.
    var previewQuads: [GlyphInstance] = []
    /// The run of the preview quads of the current pass in the glyph buffer, or `nil`.
    var previewRun: (first: Int, count: Int)?
    let atlas: GlyphAtlas
    let ring: GlyphRing
    /// The runs of the current pass, reused (PERF-01).
    var runs: [Run] = []
    /// The glyph quads of one box, reused and copied into the buffer in one step.
    private var boxGlyphs: [GlyphInstance] = []
    /// The text pass, made once (PERF-01).
    let textPass: MTLRenderPassDescriptor = {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].loadAction = .load
        return pass
    }()

    /// Makes an encoder.
    ///
    /// - Precondition: `borderCoverage` is above 0 and below 1.
    init(
        resources: InkResources,
        store: TextStore,
        cards: CardStore = CardStore(),
        atlas: GlyphAtlas,
        ring: GlyphRing,
        borderCoverage: Float = RendererConfiguration.defaultCardBorderCoverage
    ) {
        precondition(borderCoverage > 0 && borderCoverage < 1, "Border \(borderCoverage)")
        self.resources = resources
        self.store = store
        self.cards = cards
        self.atlas = atlas
        self.ring = ring
        self.borderCoverage = borderCoverage
        runs.reserveCapacity(Self.initialRunCapacity)
        boxGlyphs.reserveCapacity(Limits.maxTextLength)
        borderQuads.reserveCapacity(Limits.maxNodesPerCanvas)
        previewQuads.reserveCapacity(Limits.maxNodesPerCanvas)
    }

    /// Starts a frame. Call it after `InkEncoder.beginFrame`, which waits for a free buffer.
    func beginFrame() {
        ring.beginFrame()
    }

    /// Encodes the text boxes and the cards of `ids` from `cursor` on until the glyph buffer of
    /// the frame is full. An item that its store does not hold is skipped.
    ///
    /// - Precondition: `cursor` is a valid start in `ids`.
    /// - Returns: The new cursor. It equals `ids.count` when all boxes are drawn.
    func encodePass(
        _ context: FrameContext,
        target: InkTarget,
        ids: [GreenItem],
        cursor: Int,
        options: Options
    ) -> Int {
        precondition(cursor >= 0 && cursor <= ids.count, "Cursor \(cursor) out of \(ids.count)")
        precondition(!options.clearsScissor || options.scissor != nil, "A clear needs a scissor")
        runs.removeAll(keepingCapacity: true)
        borderQuads.removeAll(keepingCapacity: true)
        borderRun = nil
        previewQuads.removeAll(keepingCapacity: true)
        previewRun = nil
        // A pass without previews hides the atlas for its length.
        let atlas = previews
        if !options.drawsPreviews { previews = nil }
        defer { previews = atlas }
        var position = cursor
        let exponent = GlyphAtlas.exponent(pixelsPerCanvasPoint: target.pixelsPerCanvasPoint)
        for item in ids[cursor...] {
            guard let needed = quadCount(of: item) else {
                position += 1
                continue
            }
            guard needed + borderQuads.count + previewQuads.count <= ring.remaining else { break }
            guard !Self.isPastDeadline(position - cursor, options.deadline) else { break }
            append(item, target: target, exponent: exponent, frame: context.frame)
            position += 1
        }
        flushBorders()
        if !runs.isEmpty || borderRun != nil || previewRun != nil || options.clearsScissor {
            encode(into: context.commandBuffer, target: target, options: options)
        }
        assert(position >= cursor, "A text pass never goes back")
        assert(ring.used <= ring.capacity, "The glyphs fit the buffer of the frame")
        return position
    }

    /// Reading the clock costs time too, so the pass checks it every few boxes, after the first.
    private static func isPastDeadline(_ drawn: Int, _ deadline: TimeInterval) -> Bool {
        assert(drawn >= 0, "A pass draws no negative count")
        guard drawn > 0, drawn.isMultiple(of: deadlineCheckInterval) else { return false }
        return CACurrentMediaTime() > deadline
    }

    /// The map from the glyph points of one box to the pixels of a target.
    struct Mapping {
        /// The baseline origin of the box in target pixels.
        let base: SIMD2<Float>
        /// The pixels per canvas point of the target.
        let scale: Float
        /// The target pixels per atlas pixel.
        let ratio: Float
    }

    /// Returns the map of a box with its top-left corner at `origin` into a target at the atlas
    /// scale `exponent`.
    static func mapping(
        of origin: Point,
        target: InkTarget,
        exponent: Int
    ) -> Mapping {
        let pixels = target.pixelsPerCanvasPoint
        precondition(pixels > 0, "A target has pixels per canvas point, got \(pixels)")
        // The subtraction runs in Double before the conversion to Float (architecture.md 5.3).
        let delta = origin - target.camera.center
        let size = target.pixelSize
        let base = SIMD2(
            Float(size.width / 2 + delta.dx * pixels),
            Float(size.height / 2 + delta.dy * pixels)
        )
        assert(base.x.isFinite && base.y.isFinite, "A box maps to finite pixels")
        return Mapping(
            base: base,
            scale: Float(pixels),
            ratio: Float(pixels / GlyphAtlas.scale(of: exponent))
        )
    }

    /// Returns the quads that an item writes into the glyph buffer, or `nil` if its store does
    /// not hold it: the glyphs of a box, or the border and the title glyphs of a card.
    private func quadCount(of item: GreenItem) -> Int? {
        switch item {
        case .textBox(let id):
            return store.entries[id]?.layout.glyphs.count
        case .card(let id):
            guard let entry = cards.entries[id] else { return nil }
            assert((entry.layout == nil) == (entry.titleOrigin == nil), "A title has its place")
            // A border quad, a preview quad, and the title glyphs.
            return 2 + (entry.layout?.glyphs.count ?? 0)
        }
    }

    /// Writes the quads of one item into the pass.
    private func append(_ item: GreenItem, target: InkTarget, exponent: Int, frame: UInt64) {
        switch item {
        case .textBox(let id):
            guard let entry = store.entries[id] else { return }
            append(entry.layout, at: entry.origin, target: target, exponent: exponent, frame: frame)
        case .card(let id):
            guard let entry = cards.entries[id] else { return }
            appendCard(id, entry: entry, target: target, exponent: exponent, frame: frame)
        }
    }

    /// Writes the glyph quads of one layout with its top-left corner at `origin` into the buffer
    /// of the frame.
    func append(
        _ layout: TextLayout,
        at origin: Point,
        target: InkTarget,
        exponent: Int,
        frame: UInt64
    ) {
        precondition(layout.glyphs.count <= ring.remaining, "The layout fits the glyph buffer")
        precondition(
            layout.fontIndices.count == layout.glyphs.count,
            "Each of the \(layout.glyphs.count) glyphs has a font index"
        )
        let mapping = Self.mapping(of: origin, target: target, exponent: exponent)
        // The loop works on local values: each access to a stored property of a class costs a
        // dynamic exclusivity check, and a glyph needs several. Local values took the pass from
        // 29 to 17 ns per glyph (review of M5). The swap keeps the capacity of the reused list.
        var quads = boxGlyphs
        boxGlyphs = []
        quads.removeAll(keepingCapacity: true)
        let run = writeQuads(
            of: layout,
            into: &quads,
            mapping: mapping,
            exponent: exponent,
            frame: frame
        )
        flush(run)
        ring.append(contentsOf: quads)
        boxGlyphs = quads
        assert(boxGlyphs.count <= layout.glyphs.count, "One quad per glyph at most")
    }

    /// Appends the quads of the glyphs of a layout, and returns the open run of the last page.
    private func writeQuads(
        of layout: TextLayout,
        into quads: inout [GlyphInstance],
        mapping: Mapping,
        exponent: Int,
        frame: UInt64
    ) -> Run? {
        let fonts = layout.fonts
        let indices = layout.fontIndices
        // The font of a glyph changes rarely, so its number is looked up once per change.
        var fontIndex = UInt8(0)
        var fontID = atlas.fontID(of: fonts[0])
        var run = runs.last
        let first = ring.used
        for (index, glyph) in layout.glyphs.enumerated() {
            if indices[index] != fontIndex {
                fontIndex = indices[index]
                fontID = atlas.fontID(of: fonts[Int(fontIndex)])
            }
            guard
                let place = atlas.placement(
                    of: glyph.glyph,
                    font: fonts[Int(fontIndex)],
                    fontID: fontID,
                    exponent: exponent,
                    frame: frame
                ), place.page >= 0
            else { continue }
            if run?.page == place.page {
                run?.count += 1
            } else {
                flush(run)
                atlas.markUsed(page: place.page, frame: frame)
                run = Run(page: place.page, first: first + quads.count, count: 1)
            }
            let corner =
                mapping.base + glyph.position * mapping.scale + place.bearing * mapping.ratio
            quads.append(
                GlyphInstance(
                    position: corner.rounded(.toNearestOrEven),
                    size: place.size * mapping.ratio,
                    atlasOrigin: place.origin,
                    atlasSize: place.size
                )
            )
        }
        assert((run?.count ?? 1) > 0, "An open run holds a glyph")
        return run
    }

    /// Writes the open run of a box into the run list: it extends the last run or follows it.
    private func flush(_ run: Run?) {
        guard let run else { return }
        precondition(run.page >= 0, "Only glyphs with pixels make a run")
        if let last = runs.last, last.page == run.page, last.first == run.first {
            runs[runs.count - 1] = run
        } else {
            runs.append(run)
        }
        assert(runs.last?.count == run.count, "The run list ends with the run")
    }
}
