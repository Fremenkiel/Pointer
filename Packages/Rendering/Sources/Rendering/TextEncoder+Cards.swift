import Geometry
import Metal

/// The cards of a text pass: a border quad and the title glyphs of each card (architecture.md
/// 5.5, D-96).
extension TextEncoder {
    /// Writes the border quad of a card into the border list of the pass and the glyph quads of
    /// its title into the buffer of the frame.
    func appendCard(_ entry: CardStore.Entry, target: InkTarget, exponent: Int, frame: UInt64) {
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
        borderQuads.append(
            GlyphInstance(
                position: corner,
                size: SIMD2(
                    Float(entry.frame.size.width * pixels),
                    Float(entry.frame.size.height * pixels)
                ),
                atlasOrigin: SIMD2(
                    Float(lineWidth),
                    Float(RendererConfiguration.cardCornerRadius * pixels)
                ),
                atlasSize: SIMD2(borderCoverage, 0)
            )
        )
        if let layout = entry.layout, let origin = entry.titleOrigin {
            append(layout, at: origin, target: target, exponent: exponent, frame: frame)
        }
        assert(corner.x.isFinite && corner.y.isFinite, "A card maps to finite pixels")
    }

    /// Writes the border quads of the pass into the buffer of the frame as one run.
    func flushBorders() {
        guard !borderQuads.isEmpty else { return }
        precondition(borderQuads.count <= ring.remaining, "The borders fit the glyph buffer")
        borderRun = (first: ring.used, count: borderQuads.count)
        ring.append(contentsOf: borderQuads)
        borderQuads.removeAll(keepingCapacity: true)
        assert(borderRun?.count ?? 0 > 0, "A border run holds a border")
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
