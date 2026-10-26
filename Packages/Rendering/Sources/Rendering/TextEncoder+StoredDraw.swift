import Metal

/// The GPU part of the stored runs of a text pass: the expansion of the records and the draw of
/// the expanded quads (architecture.md 5.4.1, D-189, D-190).
extension TextEncoder {
    /// `true` if the current pass holds records of stored runs.
    var hasStoredRecords: Bool { !(stored?.records.isEmpty ?? true) }

    /// Encodes the vertex pass that turns the records of the pass into glyph quads at the free
    /// part of the expansion buffer. Call it before the render pass of the text. Metal tracks the
    /// buffer, so the draw of the text waits for the writes.
    func expandStored(_ commandBuffer: any MTLCommandBuffer, target: InkTarget, exponent: Int) {
        guard let stored, !stored.records.isEmpty else { return }
        let pixels = target.pixelsPerCanvasPoint
        precondition(pixels > 0, "A target has pixels per canvas point, got \(pixels)")
        guard let places = atlas.pageTable?.places, let records = stored.writeRecords(),
            let output = stored.outputBuffer()
        else {
            assertionFailure("Metal gave no buffer for the glyph expansion")
            return
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: stored.expandPass)
        else {
            assertionFailure("Metal gave no encoder for the glyph expansion")
            return
        }
        encoder.setRenderPipelineState(resources.expandGlyphsPipeline)
        encoder.setVertexValue(
            ExpandUniforms(
                scale: Float(pixels),
                ratio: Float(pixels / GlyphAtlas.scale(of: exponent)),
                recordCount: UInt32(stored.records.count),
                quadCount: UInt32(stored.passQuads),
                lineHeight: Float(TextLayout.lineHeight),
                ascent: Float(TextLayout.ascent)
            ),
            index: 0
        )
        encoder.setVertexBuffer(records.buffer, offset: records.offset, index: 1)
        // The shader reads the run buffers through their addresses, so they must be resident.
        encoder.setVertexBuffer(stored.runs.addresses, offset: 0, index: 2)
        encoder.useResources(stored.runs.buffers, usage: .read, stages: .vertex)
        encoder.setVertexBuffer(places, offset: 0, index: 3)
        encoder.setVertexBuffer(
            output,
            offset: stored.used * MemoryLayout<PagedGlyph>.stride,
            index: 4
        )
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: stored.passQuads)
        encoder.endEncoding()
    }

    /// Draws the expanded quads of the pass in one draw over the pages of the heap.
    func drawStored(
        _ encoder: any MTLRenderCommandEncoder,
        target: InkTarget,
        targetSize: SIMD2<Float>,
        exponent: Int
    ) {
        guard let stored, stored.passQuads > 0, let table = atlas.pageTable,
            let output = stored.output
        else { return }
        assert(targetSize.x > 0 && targetSize.y > 0, "A target has pixels")
        let side = Float(GlyphAtlas.pageSide(exponent: exponent))
        let pixels = target.pixelsPerCanvasPoint
        let uniforms = PagedGlyphUniforms(
            targetSize: targetSize,
            atlasSize: SIMD2(side, side),
            ratio: Float(pixels / GlyphAtlas.scale(of: exponent))
        )
        encoder.setRenderPipelineState(resources.pagedGlyphPipeline)
        encoder.setVertexBuffer(
            output,
            offset: stored.used * MemoryLayout<PagedGlyph>.stride,
            index: 0
        )
        encoder.setVertexValue(uniforms, index: 1)
        encoder.setFragmentValue(uniforms, index: 1)
        encoder.setFragmentBuffer(table.buffer, offset: 0, index: 2)
        encoder.useHeaps(table.heaps, stages: .fragment)
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: stored.passQuads
        )
    }
}
