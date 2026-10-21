import Metal

/// The Metal objects that every ink pass shares: device, queue, and pipelines.
final class InkResources {
    /// The pixel format of the committed textures: the ink coverage in red and the text
    /// coverage in green (D-82). Both are gray values, so two channels hold them at half the
    /// memory of BGRA. The eraser mask hides the red channel only.
    static let committedFormat = MTLPixelFormat.rg8Unorm
    /// The pixel format of the eraser mask: one coverage channel (D-66).
    static let maskFormat = MTLPixelFormat.r8Unorm
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
    /// Writes zero ink coverage, without blending. The redraw of an area uses it with a scissor.
    let clearPipeline: any MTLRenderPipelineState
    /// Writes zero text coverage. The redraw of a text change uses it with a scissor.
    let clearTextPipeline: any MTLRenderPipelineState
    /// Draws glyph quads from the atlas into the text channel with `max` blending (D-29, D-82).
    let glyphPipeline: any MTLRenderPipelineState
    /// Draws the rounded border of a card into the text channel with `max` blending (D-96).
    let cardBorderPipeline: any MTLRenderPipelineState

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
        clearPipeline = try Self.makeClearPipeline(device: device, library: library, mask: .red)
        clearTextPipeline = try Self.makeClearPipeline(
            device: device,
            library: library,
            mask: .green
        )
        glyphPipeline = try Self.makeGreenPipeline(device, library, "glyph")
        cardBorderPipeline = try Self.makeGreenPipeline(device, library, "cardBorder")
        compositeMaskedPipeline = try Self.makeCompositePipeline(
            device: device,
            library: library,
            fragment: "compositeMaskedFragment"
        )
        eraserPipeline = try Self.makeInkPipeline(
            device: device,
            library: library,
            functions: ("eraserVertex", "eraserFragment"),
            channel: .all,
            format: Self.maskFormat
        )
    }

    /// The ink pipeline blends with `max` (D-38, review A-06). The result of a pixel is the
    /// larger of the old and the new coverage, so overlaps do not get brighter, edges cut no
    /// notches, and the draw order does not matter. The ink writes the red channel and the text
    /// writes the green channel of the committed texture (D-82).
    private static func makeInkPipeline(
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

    /// Makes a pipeline of the text channel from the shaders `<name>Vertex` and
    /// `<name>Fragment`: green only, with `max` blending (D-82, D-96).
    private static func makeGreenPipeline(
        _ device: any MTLDevice,
        _ library: any MTLLibrary,
        _ name: String
    ) throws(RenderingError) -> any MTLRenderPipelineState {
        precondition(!name.isEmpty, "A pipeline needs a shader name")
        return try makeInkPipeline(
            device: device,
            library: library,
            functions: (name + "Vertex", name + "Fragment"),
            channel: .green
        )
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
        library: any MTLLibrary,
        mask: MTLColorWriteMask
    ) throws(RenderingError) -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = mask == .red ? "Clear ink" : "Clear text"
        descriptor.vertexFunction = library.makeFunction(name: "compositeVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "clearFragment")
        guard let attachment = descriptor.colorAttachments[0] else {
            throw .pipelineFailed("clear color attachment")
        }
        attachment.pixelFormat = committedFormat
        attachment.writeMask = mask
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
