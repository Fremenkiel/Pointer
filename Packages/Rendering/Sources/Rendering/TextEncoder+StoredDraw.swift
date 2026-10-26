import Metal

/// The GPU part of the stored runs of a text pass: one draw whose vertex shader turns the
/// records into glyph quads (architecture.md 5.4.1, D-189, D-190).
extension TextEncoder {
    /// `true` if the current pass holds records of stored runs.
    var hasStoredRecords: Bool { !(stored?.records.isEmpty ?? true) }

    /// Draws the stored glyphs of the pass in one draw over the pages of the heap. The vertex
    /// shader reads the records, the runs, and the places, and makes each quad.
    func drawStored(
        _ encoder: any MTLRenderCommandEncoder,
        target: InkTarget,
        targetSize: SIMD2<Float>,
        exponent: Int
    ) {
        guard let stored, stored.passQuads > 0, let table = atlas.pageTable,
            let places = table.places
        else { return }
        guard let records = stored.writeRecords() else {
            assertionFailure("Metal gave no buffer for the glyph records")
            return
        }
        assert(targetSize.x > 0 && targetSize.y > 0, "A target has pixels")
        let side = Float(GlyphAtlas.pageSide(exponent: exponent))
        let pixels = target.pixelsPerCanvasPoint
        let uniforms = PagedGlyphUniforms(
            targetSize: targetSize,
            atlasSize: SIMD2(side, side),
            ratio: Float(pixels / GlyphAtlas.scale(of: exponent))
        )
        encoder.setRenderPipelineState(resources.pagedGlyphPipeline)
        encoder.setVertexValue(uniforms, index: 1)
        encoder.setVertexValue(
            StoredUniforms(
                scale: Float(pixels),
                ratio: Float(pixels / GlyphAtlas.scale(of: exponent)),
                recordCount: UInt32(stored.records.count),
                lineHeight: Float(TextLayout.lineHeight),
                ascent: Float(TextLayout.ascent)
            ),
            index: 3
        )
        encoder.setVertexBuffer(records.buffer, offset: records.offset, index: 4)
        // The shader reads the run buffers through their addresses, so they must be resident.
        encoder.setVertexBuffer(stored.runs.addresses, offset: 0, index: 5)
        encoder.useResources(stored.runs.buffers, usage: .read, stages: .vertex)
        encoder.setVertexBuffer(places, offset: 0, index: 6)
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
