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

    /// Writes the glyph quads of one box into the buffer of the frame.
    private func append(_ entry: TextStore.Entry, target: InkTarget, exponent: Int, frame: UInt64) {
        precondition(entry.layout.glyphs.count <= ring.remaining, "The box fits the glyph buffer")
        let pixels = target.pixelsPerCanvasPoint
        assert(pixels > 0, "A target has pixels per canvas point")
        let ratio = Float(pixels / GlyphAtlas.scale(of: exponent))
        // The subtraction runs in Double before the conversion to Float (architecture.md 5.3).
        let delta = entry.origin - target.camera.center
        let size = target.pixelSize
        let base = SIMD2(
            Float(size.width / 2 + delta.dx * pixels),
            Float(size.height / 2 + delta.dy * pixels)
        )
        let fonts = entry.layout.fonts
        let indices = entry.layout.fontIndices
        // The font of a glyph changes rarely, so its number is looked up once per change.
        var fontIndex = UInt8(0)
        var fontID = atlas.fontID(of: fonts[0])
        boxGlyphs.removeAll(keepingCapacity: true)
        for (index, glyph) in entry.layout.glyphs.enumerated() {
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
            let corner = base + glyph.position * Float(pixels) + place.bearing * ratio
            let instance = GlyphInstance(
                position: corner.rounded(.toNearestOrEven),
                size: place.size * ratio,
                atlasOrigin: place.origin,
                atlasSize: place.size
            )
            addToRun(page: place.page, frame: frame)
            boxGlyphs.append(instance)
        }
        ring.append(contentsOf: boxGlyphs)
    }

    /// Adds a glyph to the run of its page. A new run marks its page as used by the frame.
    private func addToRun(page: Int, frame: UInt64) {
        precondition(page >= 0, "Only a glyph with pixels joins a run")
        if let last = runs.last, last.page == page {
            runs[runs.count - 1].count += 1
        } else {
            atlas.markUsed(page: page, frame: frame)
            runs.append(Run(page: page, first: ring.used + boxGlyphs.count, count: 1))
        }
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
