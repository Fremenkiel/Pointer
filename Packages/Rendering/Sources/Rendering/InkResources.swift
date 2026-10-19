import Metal

/// The Metal objects that every ink pass shares: device, queue, and pipelines.
final class InkResources {
    /// The pixel format of the committed textures: one coverage channel. Ink, text, and cards
    /// are gray values, so one channel holds them at a quarter of the memory of BGRA.
    static let committedFormat = MTLPixelFormat.r8Unorm
    /// The pixel format of the drawable (decision D-38).
    static let drawableFormat = MTLPixelFormat.bgra8Unorm

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let inkPipeline: any MTLRenderPipelineState
    let compositePipeline: any MTLRenderPipelineState
    /// Draws the composite pass through the eraser mask (D-66).
    let compositeMaskedPipeline: any MTLRenderPipelineState
    /// Stamps eraser capsules into the mask with `max` blending.
    let eraserPipeline: any MTLRenderPipelineState
    /// Writes zero coverage, without blending. The redraw of an area uses it with a scissor.
    let clearPipeline: any MTLRenderPipelineState

    /// Makes the resources on a device.
    ///
    /// - Throws: `RenderingError` if the queue, the shader library, or a pipeline fails.
    init(device: any MTLDevice) throws(RenderingError) {
        guard let queue = device.makeCommandQueue() else {
            throw .resourceUnavailable("command queue")
        }
        let library: any MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: .module)
        } catch {
            throw .resourceUnavailable("shader library: \(error.localizedDescription)")
        }
        self.device = device
        self.queue = queue
        inkPipeline = try Self.makeInkPipeline(device: device, library: library)
        compositePipeline = try Self.makeCompositePipeline(device: device, library: library)
        clearPipeline = try Self.makeClearPipeline(device: device, library: library)
        compositeMaskedPipeline = try Self.makeCompositePipeline(
            device: device,
            library: library,
            fragment: "compositeMaskedFragment"
        )
        eraserPipeline = try Self.makeInkPipeline(
            device: device,
            library: library,
            functions: ("eraserVertex", "eraserFragment")
        )
    }

    /// The ink pipeline blends with `max` (D-38, review A-06). The result of a pixel is the
    /// larger of the old and the new coverage, so overlaps do not get brighter, edges cut no
    /// notches, and the draw order does not matter.
    private static func makeInkPipeline(
        device: any MTLDevice,
        library: any MTLLibrary,
        functions: (vertex: String, fragment: String) = ("inkVertex", "inkFragment")
    ) throws(RenderingError) -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = functions.vertex
        descriptor.vertexFunction = library.makeFunction(name: functions.vertex)
        descriptor.fragmentFunction = library.makeFunction(name: functions.fragment)
        guard let attachment = descriptor.colorAttachments[0] else {
            throw .pipelineFailed("ink color attachment")
        }
        attachment.pixelFormat = committedFormat
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

    private static func makeCompositePipeline(
        device: any MTLDevice,
        library: any MTLLibrary,
        fragment: String = "compositeFragment"
    ) throws(RenderingError) -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = fragment
        descriptor.vertexFunction = library.makeFunction(name: "compositeVertex")
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        guard let attachment = descriptor.colorAttachments[0] else {
            throw .pipelineFailed("composite color attachment")
        }
        attachment.pixelFormat = drawableFormat
        assert(!attachment.isBlendingEnabled, "The composite pass replaces the drawable")
        return try makePipeline(device: device, descriptor: descriptor)
    }

    private static func makeClearPipeline(
        device: any MTLDevice,
        library: any MTLLibrary
    ) throws(RenderingError) -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Clear"
        descriptor.vertexFunction = library.makeFunction(name: "compositeVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "clearFragment")
        guard let attachment = descriptor.colorAttachments[0] else {
            throw .pipelineFailed("clear color attachment")
        }
        attachment.pixelFormat = committedFormat
        assert(!attachment.isBlendingEnabled, "The clear replaces the coverage")
        return try makePipeline(device: device, descriptor: descriptor)
    }

    private static func makePipeline(
        device: any MTLDevice,
        descriptor: MTLRenderPipelineDescriptor
    ) throws(RenderingError) -> any MTLRenderPipelineState {
        guard descriptor.vertexFunction != nil, descriptor.fragmentFunction != nil else {
            throw .pipelineFailed("\(descriptor.label ?? "pipeline") shader functions")
        }
        assert(
            descriptor.colorAttachments[0]?.pixelFormat != .invalid,
            "Pipeline has no pixel format"
        )
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw .pipelineFailed(
                "\(descriptor.label ?? "pipeline"): \(error.localizedDescription)"
            )
        }
    }

    /// Makes a texture that ink passes can draw into.
    ///
    /// - Precondition: Both sides are positive and at most the Metal limit of 16,384.
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make the texture.
    func makeTarget(
        width: Int,
        height: Int,
        format: MTLPixelFormat,
        isReadable: Bool = false
    ) throws(RenderingError) -> any MTLTexture {
        precondition(width > 0 && height > 0, "Texture size \(width) x \(height) is empty")
        precondition(
            width <= 16_384 && height <= 16_384,
            "Texture \(width) x \(height) is too large"
        )
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = isReadable ? .shared : .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw .resourceUnavailable("texture \(width) x \(height)")
        }
        return texture
    }
}
