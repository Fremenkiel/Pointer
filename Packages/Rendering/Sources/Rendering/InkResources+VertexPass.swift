import Metal

/// The pipelines of the passes without rasterization, which write buffers from the vertex stage
/// (architecture.md 5.4.1).
extension InkResources {
    /// Makes a pipeline of a vertex function that writes buffers, without rasterization and
    /// without attachments.
    static func makeVertexPassPipeline(
        _ device: any MTLDevice,
        _ library: any MTLLibrary,
        _ name: String
    ) throws(RenderingError) -> any MTLRenderPipelineState {
        precondition(!name.isEmpty, "A pipeline needs a shader name")
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = name
        guard let function = library.makeFunction(name: name) else {
            throw .pipelineFailed("\(name) shader function")
        }
        descriptor.vertexFunction = function
        descriptor.isRasterizationEnabled = false
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw .pipelineFailed("\(name): \(error.localizedDescription)")
        }
    }
}
