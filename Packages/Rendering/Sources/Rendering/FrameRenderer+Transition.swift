import Geometry
import Metal
import QuartzCore

/// The frames of an open and a leave on the renderer of the parent canvas (architecture.md 6.2
/// and 6.3, D-98, D-108, D-109, D-110).
extension FrameRenderer {
    /// Draws a frame of an open: the frozen copy of the parent with its weight, and the opened
    /// card on top. The first frame freezes the shown image and frees the committed textures.
    ///
    /// - Returns: `true` if the renderer needs another frame.
    func renderFrozenFrame(drawableSize: CGSize, drawable: DrawableSource) -> Bool {
        precondition(transition?.freezes == true, "Only an open freezes")
        guard let commandBuffer = resources.queue.makeCommandBuffer() else { return false }
        frame += 1
        let context = FrameContext(commandBuffer: commandBuffer, frame: frame)
        encoder.beginFrame(context)
        // The preview of the opened card can still arrive (D-97).
        uploadPreviews(context)
        if transition?.isFrozen == false {
            freeze(drawableSize: drawableSize, commandBuffer: commandBuffer)
        }
        RenderSignpost.begin("NextDrawable")
        let target = drawable.next()
        RenderSignpost.end("NextDrawable")
        guard let target else {
            commandBuffer.commit()
            return true
        }
        encodeTransition(
            source: transition?.frozen,
            commandBuffer: commandBuffer,
            texture: target.texture
        )
        commandBuffer.present(target)
        commitObserver?.willCommit(commandBuffer, drawable: target)
        commandBuffer.commit()
        return !(previews?.pending.isEmpty ?? true)
    }

    /// Copies the shown image into one `.r8Unorm` texture of the drawable size, and frees the
    /// committed textures and the eraser mask (D-109, D-110). Without a shown image, the open
    /// shows the canvas color behind the card.
    private func freeze(drawableSize: CGSize, commandBuffer: any MTLCommandBuffer) {
        guard var current = transition else { return }
        precondition(current.freezes, "Only an open freezes")
        let width = Int(drawableSize.width)
        let height = Int(drawableSize.height)
        if let shown = layer?.shown, width > 0, height > 0 {
            do {
                let texture = try resources.makeTarget(
                    width: width,
                    height: height,
                    format: InkResources.maskFormat
                )
                encodeFreeze(shown, into: texture, commandBuffer: commandBuffer)
                current.frozen = InkTarget(
                    texture: texture,
                    camera: camera,
                    displayScale: displayScale
                )
            } catch {
                logger.error("The frozen copy failed: \(String(describing: error))")
            }
        }
        current.isFrozen = true
        transition = current
        releaseCommittedLayer()
    }

    private func encodeFreeze(
        _ shown: InkTarget,
        into texture: any MTLTexture,
        commandBuffer: any MTLCommandBuffer
    ) {
        precondition(
            texture.pixelFormat == InkResources.maskFormat,
            "A frozen copy has one channel"
        )
        assert(shown.texture !== texture, "The freeze never reads its target")
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            logger.error("Metal gave no encoder for the frozen copy")
            return
        }
        let uniforms = CommittedLayer.compositeUniforms(
            of: shown,
            camera: camera,
            displayScale: displayScale,
            drawableSize: Size(width: Double(texture.width), height: Double(texture.height)),
            background: configuration.background
        )
        encoder.setRenderPipelineState(resources.freezePipeline)
        encoder.setFragmentTexture(shown.texture, index: 0)
        encoder.setFragmentValue(uniforms, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Draws the transition pass into the drawable: the parent image of `source` with its
    /// weight, and the opened card at full weight (D-108).
    func encodeTransition(
        source: InkTarget?,
        commandBuffer: any MTLCommandBuffer,
        texture: any MTLTexture
    ) {
        guard let transition else { return }
        precondition(texture.pixelFormat == InkResources.drawableFormat, "Drawable is BGRA")
        // The frame draws the preview of the opened card, so a full atlas must keep its slot
        // during the flight (review after M8, section 3.2, item 6).
        if let previews, let entry = previews.entries[transition.card] {
            previews.markUsed(entry, frame: frame)
        }
        assert(source == nil || source?.texture !== texture, "A pass never reads its target")
        let pass = compositePass
        pass.colorAttachments[0].texture = texture
        let made = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        // The descriptor lives on, so it must not hold the drawable after the frame.
        pass.colorAttachments[0].texture = nil
        guard let encoder = made else { return }
        let size = Size(width: Double(texture.width), height: Double(texture.height))
        let uniforms = transitionUniforms(transition, source: source, drawableSize: size)
        encoder.setRenderPipelineState(resources.transitionPipeline)
        encoder.setFragmentTexture(source?.texture ?? resources.placeholder, index: 0)
        encoder.setFragmentTexture(previews?.texture ?? resources.placeholder, index: 1)
        encoder.setFragmentValue(uniforms, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Returns the values of a transition frame at the current camera.
    private func transitionUniforms(
        _ transition: FrameTransition,
        source: InkTarget?,
        drawableSize: Size
    ) -> TransitionUniforms {
        precondition(displayScale > 0, "Display scale must be positive")
        precondition(drawableSize.width > 0 && drawableSize.height > 0, "A drawable has pixels")
        let mapping = source.map {
            CommittedLayer.compositeUniforms(
                of: $0,
                camera: camera,
                displayScale: displayScale,
                drawableSize: drawableSize,
                background: configuration.background
            )
        }
        var cardRect = SIMD4<Float>(repeating: -1)
        if let frame = cards.entries[transition.card]?.frame {
            let pixels = camera.zoom * displayScale
            let low = (frame.origin - camera.center) * pixels
            cardRect = SIMD4(
                Float(drawableSize.width / 2 + low.dx),
                Float(drawableSize.height / 2 + low.dy),
                Float(drawableSize.width / 2 + low.dx + frame.size.width * pixels),
                Float(drawableSize.height / 2 + low.dy + frame.size.height * pixels)
            )
        }
        return TransitionUniforms(
            background: SIMD4(configuration.background, 1),
            cardRect: cardRect,
            previewRect: previewRect(of: transition),
            scale: mapping?.scale ?? .zero,
            offset: mapping?.offset ?? .zero,
            textureSize: mapping?.textureSize ?? SIMD2(1, 1),
            parentWeight: Float(min(max(transition.parentWeight, 0), 1)),
            borderCoverage: configuration.cardBorderCoverage,
            borderHalfWidth: Float(RendererConfiguration.cardBorderWidth * displayScale / 2),
            cornerRadius: Float(
                RendererConfiguration.cardCornerRadius * camera.zoom * displayScale
            ),
            hasSource: mapping == nil ? 0 : 1,
            fillCoverage: configuration.cardFillCoverage
        )
    }

    /// Returns the place of the preview of the opened card in the atlas, from 0 to 1, or zero
    /// without a preview.
    private func previewRect(of transition: FrameTransition) -> SIMD4<Float> {
        guard let previews, let entry = previews.entries[transition.card] else { return .zero }
        let width = Float(previews.texture.width)
        let height = Float(previews.texture.height)
        assert(width > 0 && height > 0, "The atlas has pixels")
        return SIMD4(
            Float(entry.x) / width,
            Float(entry.y) / height,
            Float(entry.width) / width,
            Float(entry.height) / height
        )
    }
}
