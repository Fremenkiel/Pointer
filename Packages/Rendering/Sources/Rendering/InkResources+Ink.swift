import Metal

/// The ink pipeline of the resources.
extension InkResources {
    /// The ink pipeline blends with `max` (D-38, review A-06). The result of a pixel is the
    /// larger of the old and the new coverage, so overlaps do not get brighter, edges cut no
    /// notches, and the draw order does not matter. The ink writes the red channel and the text
    /// writes the green channel of the committed texture (D-82).
    static func makeInkPipeline(
        device: any MTLDevice,
        library: any MTLLibrary,
        functions: (vertex: String, fragment: String) = ("inkVertex", "inkFragment"),
        channel: MTLColorWriteMask = .red,
        format: MTLPixelFormat = committedFormat
    ) throws(RenderingError) -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = functions.vertex
        descriptor.vertexFunction = library.makeFunction(name: functions.vertex)
        descriptor.fragmentFunction = library.makeFunction(name: functions.fragment)
        guard let attachment = descriptor.colorAttachments[0] else {
            throw .pipelineFailed("ink color attachment")
        }
        attachment.pixelFormat = format
        attachment.writeMask = channel
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .max
        attachment.alphaBlendOperation = .max
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .one
        assert(attachment.rgbBlendOperation == .max, "Ink blends with max (D-38)")
        return try makePipeline(device: device, descriptor: descriptor)
    }
}
