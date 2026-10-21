import Geometry
import Metal

/// The composite pass of the frame work (architecture.md 5.2).
extension FrameRenderer {
    /// Draws the shown committed texture into the drawable: the canvas color, mixed with white
    /// by the larger coverage of the two channels, with the eraser mask over the red channel
    /// (architecture.md 5.2, D-82, D-106).
    func encodeComposite(
        layer: CommittedLayer,
        commandBuffer: any MTLCommandBuffer,
        texture: any MTLTexture
    ) {
        precondition(
            texture.pixelFormat == InkResources.drawableFormat,
            "Drawable format is not BGRA"
        )
        let pass = compositePass
        pass.colorAttachments[0].texture = texture
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        // The descriptor lives on, so it must not hold the drawable after the frame.
        pass.colorAttachments[0].texture = nil
        guard let encoder else {
            assertionFailure("Metal gave no render encoder for the composite pass")
            return
        }
        #if DEBUG
            // A label costs two allocations per frame and helps only in a GPU capture.
            encoder.label = "Composite"
        #endif
        if let front = layer.shown {
            let size = Size(width: Double(texture.width), height: Double(texture.height))
            // The mask uses the mapping of the front texture, so a fallback shows no mask.
            let mask =
                eraserMask.hasStamps && front.texture === layer.front?.texture ? layer.mask : nil
            encoder.setRenderPipelineState(
                mask == nil ? resources.compositePipeline : resources.compositeMaskedPipeline
            )
            encoder.setFragmentTexture(front.texture, index: 0)
            if let mask {
                encoder.setFragmentTexture(mask, index: 1)
            }
            encoder.setFragmentValue(
                layer.compositeUniforms(
                    camera: camera,
                    displayScale: displayScale,
                    drawableSize: size,
                    background: configuration.background
                ),
                index: 0
            )
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }
}
