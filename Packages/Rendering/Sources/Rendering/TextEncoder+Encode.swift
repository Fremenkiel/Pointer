import Metal

/// The Metal part of a text pass: the clear, the card borders, and the glyph runs (architecture.md
/// 5.4 and 5.5).
extension TextEncoder {
    /// Encodes the pass of the current runs into `target`: the clear of the scissor, the card
    /// borders, and the glyph runs, in this order. All of them write green with `max`, so the
    /// order of the borders and the glyphs does not matter (D-96).
    ///
    /// - Precondition: The pass draws or clears.
    func encode(
        into commandBuffer: any MTLCommandBuffer,
        target: InkTarget,
        options: Options
    ) {
        precondition(
            !runs.isEmpty || borderRun != nil || previewRun != nil || options.clearsScissor,
            "A text pass draws or clears"
        )
        assert(runs.allSatisfy { $0.count > 0 }, "Each glyph run holds a glyph")
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
        let size = target.pixelSize
        let targetSize = SIMD2(Float(size.width), Float(size.height))
        encodeBorders(encoder, targetSize: targetSize)
        encodePreviews(encoder, targetSize: targetSize)
        encodeGlyphRuns(encoder, targetSize: targetSize)
        encoder.endEncoding()
    }

    /// Draws the glyph runs of the pass, one instanced draw per run.
    private func encodeGlyphRuns(_ encoder: any MTLRenderCommandEncoder, targetSize: SIMD2<Float>) {
        guard !runs.isEmpty else { return }
        assert(targetSize.x > 0 && targetSize.y > 0, "A target has pixels")
        assert(runs.allSatisfy { $0.page >= 0 }, "Each glyph run names an atlas page")
        encoder.setRenderPipelineState(resources.glyphPipeline)
        for run in runs {
            guard let page = atlas.pages[run.page] else { continue }
            let uniforms = GlyphUniforms(
                targetSize: targetSize,
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
    }
}
