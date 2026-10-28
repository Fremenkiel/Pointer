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
        /// ink of a build does (task 2.4 of the M5 plan).
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

    /// The pipelines and the device.
    let resources: InkResources
    let store: TextStore
    /// The cards of the canvas, for the cards in the list of a pass (D-96).
    let cards: CardStore
    /// The coverage of a card border (D-96).
    let borderCoverage: Float
    /// The coverage of the body of a card (D-116).
    let fillCoverage: Float
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
    /// The glyph coverage on the GPU.
    let atlas: GlyphAtlas
    /// The glyph buffers of the frames in flight.
    let ring: GlyphRing
    /// The stored glyph runs, or `nil` for the CPU path only (architecture.md 5.4.1).
    var stored: StoredText?
    /// The stored quads per frame and the run budget of the stored runs that the encoder makes at
    /// the first layout that needs them, or `nil` for the CPU path only.
    let storedLimits: (capacity: Int, runBudget: Int)?
    /// `true` after a layout of `StoredText.minimumGlyphs` glyphs or more took the CPU path,
    /// because the stored runs did not exist yet. The next pass makes them.
    var wantsStored = false
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
        stored: StoredText? = nil,
        storedLimits: (capacity: Int, runBudget: Int)? = nil,
        borderCoverage: Float = RendererConfiguration.defaultCardBorderCoverage,
        fillCoverage: Float = RendererConfiguration.defaultCardFillCoverage
    ) {
        precondition(stored == nil || atlas.pageTable != nil, "Stored runs need a page table")
        precondition(borderCoverage > 0 && borderCoverage < 1, "Border \(borderCoverage)")
        self.resources = resources
        self.store = store
        self.cards = cards
        self.atlas = atlas
        self.ring = ring
        self.stored = stored
        self.storedLimits = storedLimits
        self.borderCoverage = borderCoverage
        self.fillCoverage = fillCoverage
        runs.reserveCapacity(Self.initialRunCapacity)
        boxGlyphs.reserveCapacity(Limits.maxTextLength)
        borderQuads.reserveCapacity(Limits.maxNodesPerCanvas)
        previewQuads.reserveCapacity(Limits.maxNodesPerCanvas)
    }

    /// Starts a frame. Call it after `InkEncoder.beginFrame`, which waits for a free buffer.
    func beginFrame(buildBudget: Double = StoredText.buildBudget) {
        ring.beginFrame()
        stored?.beginFrame(now: CACurrentMediaTime(), budget: buildBudget)
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
        if wantsStored { startStored() }
        stored?.beginPass(deadline: options.deadline)
        for item in ids[cursor...] {
            guard let room = room(for: item) else {
                position += 1
                continue
            }
            guard room.cpu || room.stored else { break }
            guard !Self.isPastDeadline(position - cursor, options.deadline) else { break }
            let place = Place(target: target, exponent: exponent, frame: context.frame)
            guard append(item, place, allowsCPU: room.cpu) else { break }
            position += 1
        }
        flushBorders()
        let draws = !runs.isEmpty || borderRun != nil || previewRun != nil || hasStoredRecords
        if draws || options.clearsScissor {
            encode(
                into: context.commandBuffer,
                target: target,
                exponent: exponent,
                options: options
            )
        }
        stored?.endPass()
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
        return Mapping(
            base: target.pixelCorner(of: origin),
            scale: Float(pixels),
            ratio: Float(pixels / GlyphAtlas.scale(of: exponent))
        )
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
        var run = runs.last
        let first = ring.used
        var placed = PlacedGlyphs(of: layout, in: atlas, exponent: exponent, frame: frame)
        // The glyph count bounds the loop (FLOW-03).
        while let item = placed.next() {
            guard let place = item.place, place.page >= 0 else { continue }
            let glyph = item.glyph
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
    }
}
