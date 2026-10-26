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

    /// The GPU.
    let device: any MTLDevice
    /// The command queue of the renderer.
    let queue: any MTLCommandQueue
    /// Draws the ink coverage of the strokes.
    let inkPipeline: any MTLRenderPipelineState
    /// Draws the composite pass without the eraser mask.
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
    /// Draws the glyph quads of the stored runs from the atlas pages of the heap (D-189).
    let pagedGlyphPipeline: any MTLRenderPipelineState
    /// Turns the records of a text pass into glyph quads, in a vertex pass without
    /// rasterization (D-190).
    let expandGlyphsPipeline: any MTLRenderPipelineState
    /// Draws the rounded border of a card into the text channel with `max` blending (D-96).
    let cardBorderPipeline: any MTLRenderPipelineState
    /// Writes the larger coverage of the two channels into one channel, for a preview (D-97).
    let previewResolvePipeline: any MTLRenderPipelineState
    /// Writes the coverage that the composite shows into one channel: the frozen copy (D-109).
    let freezePipeline: any MTLRenderPipelineState
    /// Draws a frame of an open or a leave into the drawable (D-98, D-108).
    let transitionPipeline: any MTLRenderPipelineState
    /// Draws card previews from the atlas into the text channel, cut to the rounded rectangle
    /// of each card, with `max` blending (D-97).
    let cardPreviewPipeline: any MTLRenderPipelineState
    /// Draws a frame of a pinch-out exit into the drawable (CARD-05, D-109).
    let pinchPipeline: any MTLRenderPipelineState
    /// A texture of one pixel for a pass argument that a frame does not read.
    let placeholder: any MTLTexture

    /// Makes resources with the pipelines of `other` and a command queue of their own, so
    /// that each renderer keeps its own GPU order (m10-plan.md task 3.3).
    ///
    /// - Throws: `RenderingError.resourceUnavailable` if the device makes no queue.
    init(sharingPipelinesOf other: InkResources) throws(RenderingError) {
        guard let queue = other.device.makeCommandQueue() else {
            throw .resourceUnavailable("command queue")
        }
        device = other.device
        self.queue = queue
        inkPipeline = other.inkPipeline
        compositePipeline = other.compositePipeline
        compositeMaskedPipeline = other.compositeMaskedPipeline
        eraserPipeline = other.eraserPipeline
        clearPipeline = other.clearPipeline
        clearTextPipeline = other.clearTextPipeline
        glyphPipeline = other.glyphPipeline
        pagedGlyphPipeline = other.pagedGlyphPipeline
        expandGlyphsPipeline = other.expandGlyphsPipeline
        cardBorderPipeline = other.cardBorderPipeline
        previewResolvePipeline = other.previewResolvePipeline
        freezePipeline = other.freezePipeline
        transitionPipeline = other.transitionPipeline
        cardPreviewPipeline = other.cardPreviewPipeline
        pinchPipeline = other.pinchPipeline
        placeholder = other.placeholder
    }

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
        placeholder = try Self.makePlaceholder(device)
        inkPipeline = try Self.makeInkPipeline(device: device, library: library)
        compositePipeline = try Self.makeCompositePipeline(device: device, library: library)
        clearPipeline = try Self.makeClearPipeline(device: device, library: library, mask: .red)
        clearTextPipeline = try Self.makeClearPipeline(
            device: device,
            library: library,
            mask: .green
        )
        glyphPipeline = try Self.makeGreenPipeline(device, library, "glyph")
        pagedGlyphPipeline = try Self.makeGreenPipeline(device, library, "pagedGlyph")
        expandGlyphsPipeline = try Self.makeVertexPassPipeline(device, library, "expandGlyphs")
        cardBorderPipeline = try Self.makeGreenPipeline(device, library, "cardBorder")
        cardPreviewPipeline = try Self.makeGreenPipeline(device, library, "cardPreview")
        previewResolvePipeline = try Self.makeResolvePipeline(device, library, "previewResolve")
        freezePipeline = try Self.makeResolvePipeline(device, library, "freeze")
        (compositeMaskedPipeline, transitionPipeline) = try Self.makeCompositeVariants(
            device,
            library
        )
        pinchPipeline = try Self.makeComposite(device, library, "pinchFragment")
        eraserPipeline = try Self.makeInkPipeline(
            device: device,
            library: library,
            functions: ("eraserVertex", "eraserFragment"),
            channel: .all,
            format: Self.maskFormat
        )
    }

    /// Makes a pipeline into the drawable with the full-screen vertex shader and `fragment`.
    private static func makeComposite(
        _ device: any MTLDevice,
        _ library: any MTLLibrary,
        _ fragment: String
    ) throws(RenderingError) -> any MTLRenderPipelineState {
        precondition(!fragment.isEmpty, "A pipeline needs a shader name")
        return try makeCompositePipeline(device: device, library: library, fragment: fragment)
    }

    /// Makes the composite through the eraser mask (D-66) and the transition pass (D-108).
    private static func makeCompositeVariants(
        _ device: any MTLDevice,
        _ library: any MTLLibrary
    ) throws(RenderingError) -> (any MTLRenderPipelineState, any MTLRenderPipelineState) {
        let masked = try makeCompositePipeline(
            device: device,
            library: library,
            fragment: "compositeMaskedFragment"
        )
        let transition = try makeCompositePipeline(
            device: device,
            library: library,
            fragment: "transitionFragment"
        )
        assert(masked !== transition, "Two pipelines")
        return (masked, transition)
    }

    /// Makes the texture of one pixel for pass arguments that a frame does not read.
    private static func makePlaceholder(
        _ device: any MTLDevice
    ) throws(RenderingError) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: maskFormat,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw .resourceUnavailable("placeholder texture")
        }
        assert(texture.width == 1, "One pixel")
        return texture
    }

    /// Makes a full-screen pipeline from the shader `<name>Fragment` that writes one
    /// `.r8Unorm` channel without blending: the resolve of a preview or the frozen copy.
    private static func makeResolvePipeline(
        _ device: any MTLDevice,
        _ library: any MTLLibrary,
        _ name: String
    ) throws(RenderingError) -> any MTLRenderPipelineState {
        precondition(!name.isEmpty, "A pipeline needs a shader name")
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = name
        descriptor.vertexFunction = library.makeFunction(name: "compositeVertex")
        descriptor.fragmentFunction = library.makeFunction(name: name + "Fragment")
        guard let attachment = descriptor.colorAttachments[0] else {
            throw .pipelineFailed("\(name) color attachment")
        }
        attachment.pixelFormat = maskFormat
        assert(!attachment.isBlendingEnabled, "The resolve replaces the pixels")
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

    /// Makes a render pipeline from `descriptor`.
    ///
    /// - Precondition: The first color attachment has a pixel format.
    /// - Throws: `RenderingError.pipelineFailed` without a vertex or a fragment function, or if
    ///   Metal cannot make the pipeline.
    static func makePipeline(
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
