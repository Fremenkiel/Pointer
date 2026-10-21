import Geometry
import Metal
import Model
import QuartzCore

/// Encodes text passes: one glyph quad per glyph from the atlas into the text channel of a
/// committed texture (architecture.md 5.4, D-29, D-82).
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
    }

    /// The pass reads the clock once per this number of boxes.
    static let deadlineCheckInterval = 8

    /// The glyph quads of one atlas page in the buffer of the frame.
    private struct Run {
        let page: Int
        let first: Int
        var count: Int
    }

    /// The first capacity of the run list. It grows once to the most runs of a pass.
    private static let initialRunCapacity = 64

    private let resources: InkResources
    private let store: TextStore
    let atlas: GlyphAtlas
    let ring: GlyphRing
    /// The runs of the current pass, reused (PERF-01).
    private var runs: [Run] = []
    /// The glyph quads of one box, reused and copied into the buffer in one step.
    private var boxGlyphs: [GlyphInstance] = []
    /// The text pass, made once (PERF-01).
    private let textPass: MTLRenderPassDescriptor = {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].loadAction = .load
        return pass
    }()

    /// Makes an encoder.
    init(resources: InkResources, store: TextStore, atlas: GlyphAtlas, ring: GlyphRing) {
        self.resources = resources
        self.store = store
        self.atlas = atlas
        self.ring = ring
        runs.reserveCapacity(Self.initialRunCapacity)
        boxGlyphs.reserveCapacity(Limits.maxTextLength)
    }

    /// Starts a frame. Call it after `InkEncoder.beginFrame`, which waits for a free buffer.
    func beginFrame() {
        ring.beginFrame()
    }

    /// Encodes the text boxes of `ids` from `cursor` on until the glyph buffer of the frame is
    /// full. A box that the store does not hold is skipped.
    ///
    /// - Precondition: `cursor` is a valid start in `ids`.
    /// - Returns: The new cursor. It equals `ids.count` when all boxes are drawn.
    func encodePass(
        _ context: FrameContext,
        target: InkTarget,
        ids: [TextBoxID],
        cursor: Int,
        options: Options
    ) -> Int {
        precondition(cursor >= 0 && cursor <= ids.count, "Cursor \(cursor) out of \(ids.count)")
        precondition(!options.clearsScissor || options.scissor != nil, "A clear needs a scissor")
        runs.removeAll(keepingCapacity: true)
        var position = cursor
        let exponent = GlyphAtlas.exponent(pixelsPerCanvasPoint: target.pixelsPerCanvasPoint)
        for id in ids[cursor...] {
            guard let entry = store.entries[id] else {
                position += 1
                continue
            }
            guard entry.layout.glyphs.count <= ring.remaining else { break }
            guard !Self.isPastDeadline(position - cursor, options.deadline) else { break }
            append(entry, target: target, exponent: exponent, frame: context.frame)
            position += 1
        }
        if !runs.isEmpty || options.clearsScissor {
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
    private struct Mapping {
        /// The baseline origin of the box in target pixels.
        let base: SIMD2<Float>
        /// The pixels per canvas point of the target.
        let scale: Float
        /// The target pixels per atlas pixel.
        let ratio: Float
    }

    /// Returns the map of a box into a target at the atlas scale `exponent`.
    private static func mapping(
        of entry: TextStore.Entry,
        target: InkTarget,
        exponent: Int
    ) -> Mapping {
        let pixels = target.pixelsPerCanvasPoint
        precondition(pixels > 0, "A target has pixels per canvas point, got \(pixels)")
        // The subtraction runs in Double before the conversion to Float (architecture.md 5.3).
        let delta = entry.origin - target.camera.center
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

    /// Writes the glyph quads of one box into the buffer of the frame.
    private func append(_ entry: TextStore.Entry, target: InkTarget, exponent: Int, frame: UInt64) {
        precondition(entry.layout.glyphs.count <= ring.remaining, "The box fits the glyph buffer")
        precondition(
            entry.layout.fontIndices.count == entry.layout.glyphs.count,
            "Each of the \(entry.layout.glyphs.count) glyphs has a font index"
        )
        let mapping = Self.mapping(of: entry, target: target, exponent: exponent)
        // The loop works on local values: each access to a stored property of a class costs a
        // dynamic exclusivity check, and a glyph needs several. Local values took the pass from
        // 29 to 17 ns per glyph (review of M5). The swap keeps the capacity of the reused list.
        var quads = boxGlyphs
        boxGlyphs = []
        quads.removeAll(keepingCapacity: true)
        let run = writeQuads(
            of: entry.layout,
            into: &quads,
            mapping: mapping,
            exponent: exponent,
            frame: frame
        )
        flush(run)
        ring.append(contentsOf: quads)
        boxGlyphs = quads
        assert(boxGlyphs.count <= entry.layout.glyphs.count, "One quad per glyph at most")
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

    private func encode(
        into commandBuffer: any MTLCommandBuffer,
        target: InkTarget,
        options: Options
    ) {
        precondition(!runs.isEmpty || options.clearsScissor, "A text pass draws or clears")
        let pass = textPass
        pass.colorAttachments[0].texture = target.texture
        let made = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        // The descriptor lives on, so it must not hold the texture after the pass.
        pass.colorAttachments[0].texture = nil
        guard let encoder = made else {
            assertionFailure("Metal gave no render encoder for the text pass")
            return
        }
        if let scissor = options.scissor {
            encoder.setScissorRect(scissor)
        }
        if options.clearsScissor {
            encoder.setRenderPipelineState(resources.clearTextPipeline)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.setRenderPipelineState(resources.glyphPipeline)
        let size = target.pixelSize
        for run in runs {
            guard let page = atlas.pages[run.page] else { continue }
            let uniforms = GlyphUniforms(
                targetSize: SIMD2(Float(size.width), Float(size.height)),
                atlasSize: SIMD2(Float(page.texture.width), Float(page.texture.height))
            )
            encoder.setVertexBuffer(
                ring.buffer,
                offset: run.first * MemoryLayout<GlyphInstance>.stride,
                index: 0
            )
            encoder.setVertexValue(uniforms, index: 1)
            encoder.setFragmentValue(uniforms, index: 1)
            encoder.setFragmentTexture(page.texture, index: 0)
            encoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: run.count
            )
        }
        encoder.endEncoding()
    }
}
