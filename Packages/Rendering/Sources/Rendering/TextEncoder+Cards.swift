import Geometry
import Metal
import Model

/// The cards of a text pass: a border quad and the title glyphs of each card (architecture.md
/// 5.5, D-96).
extension TextEncoder {
    /// Writes the border quad of a card into the border list of the pass and the glyph quads of
    /// its title into the buffer of the frame.
    func appendCard(
        _ id: CardID,
        entry: CardStore.Entry,
        target: InkTarget,
        exponent: Int,
        frame: UInt64
    ) {
        let pixels = target.pixelsPerCanvasPoint
        precondition(pixels > 0, "A target has pixels per canvas point, got \(pixels)")
        // The subtraction runs in Double before the conversion to Float (architecture.md 5.3).
        let delta = entry.frame.origin - target.camera.center
        let size = target.pixelSize
        let corner = SIMD2(
            Float(size.width / 2 + delta.dx * pixels),
            Float(size.height / 2 + delta.dy * pixels)
        )
        let lineWidth = RendererConfiguration.cardBorderWidth * target.displayScale
        let quadSize = SIMD2(
            Float(entry.frame.size.width * pixels),
            Float(entry.frame.size.height * pixels)
        )
        appendPreview(of: id, entry: entry, corner: corner, size: quadSize, frame: frame)
        borderQuads.append(
            GlyphInstance(
                position: corner,
                size: quadSize,
                atlasOrigin: SIMD2(
                    Float(lineWidth),
                    Float(RendererConfiguration.cardCornerRadius * pixels)
                ),
                atlasSize: SIMD2(borderCoverage, fillCoverage)
            )
        )
        if let layout = entry.layout, let origin = entry.titleOrigin {
            append(layout, at: origin, target: target, exponent: exponent, frame: frame)
        }
        assert(corner.x.isFinite && corner.y.isFinite, "A card maps to finite pixels")
    }

    /// Writes the preview quad of a card that has its preview in the atlas, and asks for the
    /// preview if it is missing or smaller than the card on the screen (D-97).
    private func appendPreview(
        of id: CardID,
        entry: CardStore.Entry,
        corner: SIMD2<Float>,
        size: SIMD2<Float>,
        frame: UInt64
    ) {
        guard let previews else { return }
        precondition(size.x >= 0 && size.y >= 0, "A card has a size on the screen")
        let step = PreviewAtlas.step(forPixels: Double(max(size.x, size.y)))
        let aspect = entry.frame.size.width / entry.frame.size.height
        guard let preview = previews.entries[id] else {
            previews.want(id, bounds: entry.bounds, step: step, cardAspect: aspect)
            return
        }
        if preview.step < step {
            previews.want(id, bounds: entry.bounds, step: step, cardAspect: aspect)
        }
        previews.markUsed(preview, frame: frame)
        previewQuads.append(
            GlyphInstance(
                position: corner,
                size: size,
                atlasOrigin: SIMD2(Float(preview.x), Float(preview.y)),
                atlasSize: SIMD2(Float(preview.width), Float(preview.height))
            )
        )
        assert(preview.width <= preview.step && preview.height <= preview.step, "Preview size")
    }

    /// Writes the border quads and the preview quads of the pass into the buffer of the frame,
    /// each as one run.
    func flushBorders() {
        precondition(
            borderQuads.count + previewQuads.count <= ring.remaining,
            "The cards fit the glyph buffer"
        )
        if !previewQuads.isEmpty {
            previewRun = (first: ring.used, count: previewQuads.count)
            ring.append(contentsOf: previewQuads)
            previewQuads.removeAll(keepingCapacity: true)
        }
        if !borderQuads.isEmpty {
            borderRun = (first: ring.used, count: borderQuads.count)
            ring.append(contentsOf: borderQuads)
            borderQuads.removeAll(keepingCapacity: true)
        }
    }

    /// Draws the preview run of the pass from the atlas: a preview quad samples its slot and
    /// writes green with `max`, cut to the rounded rectangle of the card (D-97). `radius` is the
    /// corner radius of the cards in target pixels.
    func encodePreviews(
        _ encoder: any MTLRenderCommandEncoder,
        targetSize: SIMD2<Float>,
        radius: Float
    ) {
        guard let run = previewRun, let atlas = previews?.texture else { return }
        precondition(run.count > 0, "A preview run holds a preview")
        assert(run.first + run.count <= ring.used, "The preview run lies in the written buffer")
        let uniforms = CardPreviewUniforms(
            targetSize: targetSize,
            atlasSize: SIMD2(Float(atlas.width), Float(atlas.height)),
            radius: radius
        )
        encoder.setRenderPipelineState(resources.cardPreviewPipeline)
        encoder.setVertexBuffer(
            ring.buffer,
            offset: run.first * MemoryLayout<GlyphInstance>.stride,
            index: 0
        )
        encoder.setVertexValue(uniforms, index: 1)
        encoder.setFragmentValue(uniforms, index: 1)
        encoder.setFragmentTexture(atlas, index: 0)
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: run.count
        )
    }

    /// Draws the border run of the pass, if any.
    func encodeBorders(_ encoder: any MTLRenderCommandEncoder, targetSize: SIMD2<Float>) {
        guard let run = borderRun else { return }
        precondition(run.count > 0, "A border run holds a border")
        assert(run.first + run.count <= ring.used, "The border run lies in the written buffer")
        let uniforms = GlyphUniforms(targetSize: targetSize, atlasSize: SIMD2(1, 1))
        encoder.setRenderPipelineState(resources.cardBorderPipeline)
        encoder.setVertexBuffer(
            ring.buffer,
            offset: run.first * MemoryLayout<GlyphInstance>.stride,
            index: 0
        )
        encoder.setVertexValue(uniforms, index: 1)
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: run.count
        )
    }
}
