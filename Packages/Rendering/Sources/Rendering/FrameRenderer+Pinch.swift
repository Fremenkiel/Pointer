import Geometry
import Metal
import Model

/// The frames of a pinch-out exit on the renderer of a child (CARD-05, D-109).
extension FrameRenderer {
    /// Draws a frame of a pinch-out exit: the frozen parent with the weight of the progress,
    /// and the child image inside its shrinking card. Without a frozen parent, the canvas color
    /// shows around the card.
    func encodePinch(
        _ exit: PinchExit,
        layer: CommittedLayer,
        commandBuffer: any MTLCommandBuffer,
        texture: any MTLTexture
    ) {
        precondition(texture.pixelFormat == InkResources.drawableFormat, "Drawable is BGRA")
        let pass = compositePass
        pass.colorAttachments[0].texture = texture
        let made = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        // The descriptor lives on, so it must not hold the drawable after the frame.
        pass.colorAttachments[0].texture = nil
        guard let encoder = made else { return }
        let size = Size(width: Double(texture.width), height: Double(texture.height))
        let uniforms = pinchUniforms(exit, shown: layer.shown, drawableSize: size)
        assert(layer.shown?.texture !== texture, "The pinch pass never reads its target")
        encoder.setRenderPipelineState(resources.pinchPipeline)
        encoder.setFragmentTexture(parentImage?.texture ?? resources.placeholder, index: 0)
        encoder.setFragmentTexture(layer.shown?.texture ?? resources.placeholder, index: 1)
        encoder.setFragmentValue(uniforms, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Returns the values of a pinch frame at the camera of the child.
    private func pinchUniforms(
        _ exit: PinchExit,
        shown: InkTarget?,
        drawableSize: Size
    ) -> PinchUniforms {
        precondition(displayScale > 0, "Display scale must be positive")
        precondition(drawableSize.width > 0 && drawableSize.height > 0, "A drawable has pixels")
        let parentCamera = exit.parentCamera
        let card = cardRect(exit, camera: parentCamera, drawableSize: drawableSize)
        let start = cardRect(
            PinchExit(card: exit.card, cover: exit.cover, leave: exit.leave),
            camera: exit.cover,
            drawableSize: drawableSize
        )
        let parent = parentImage.map { mapping(of: $0, camera: parentCamera, drawableSize) }
        // The child image keeps the scale of the minimum zoom inside the card.
        let childCamera = Camera(center: camera.center, zoom: max(camera.zoom, Limits.minZoom))
        let child = shown.map { mapping(of: $0, camera: childCamera, drawableSize) }
        let pixels = (exit.card == nil ? 1 : parentCamera.zoom) * displayScale
        return PinchUniforms(
            background: SIMD4(configuration.background, 1),
            cardRect: card,
            parentScale: parent?.scale ?? .zero,
            parentOffset: parent?.offset ?? .zero,
            parentSize: parent?.textureSize ?? SIMD2(1, 1),
            childScale: child?.scale ?? .zero,
            childOffset: child?.offset ?? .zero,
            childSize: child?.textureSize ?? SIMD2(1, 1),
            screenCenter: SIMD2(Float(drawableSize.width / 2), Float(drawableSize.height / 2)),
            parentWeight: parent == nil ? 0 : Float(min(max(exit.progress, 0), 1)),
            borderCoverage: configuration.cardBorderCoverage,
            borderHalfWidth: Float(RendererConfiguration.cardBorderWidth * displayScale / 2),
            cornerRadius: Float(RendererConfiguration.cardCornerRadius * pixels),
            shrink: Float(max(card.z - card.x, 1) / max(start.z - start.x, 1))
        )
    }

    /// Returns the map from a drawable pixel to a pixel of `target` at `camera`.
    private func mapping(
        of target: InkTarget,
        camera: Camera,
        _ drawableSize: Size
    ) -> CompositeUniforms {
        precondition(target.pixelsPerCanvasPoint > 0, "A target has pixels per canvas point")
        assert(drawableSize.width > 0 && drawableSize.height > 0, "A drawable has pixels")
        return CommittedLayer.compositeUniforms(
            of: target,
            camera: camera,
            displayScale: displayScale,
            drawableSize: drawableSize,
            background: configuration.background
        )
    }

    /// Returns the card rectangle in drawable pixels: the card frame through the parent camera,
    /// or a rectangle of the screen that shrinks toward its center without a known frame.
    private func cardRect(
        _ exit: PinchExit,
        camera: Camera,
        drawableSize: Size
    ) -> SIMD4<Float> {
        let half = Vector(dx: drawableSize.width / 2, dy: drawableSize.height / 2)
        guard let frame = exit.card else {
            let progress = min(max(exit.progress, 0), 1)
            let scale = 1 - (1 - PinchExit.unknownCardScale) * progress
            return SIMD4(
                Float(half.dx * (1 - scale)),
                Float(half.dy * (1 - scale)),
                Float(half.dx * (1 + scale)),
                Float(half.dy * (1 + scale))
            )
        }
        let pixels = camera.zoom * displayScale
        let low = (frame.origin - camera.center) * pixels + half
        assert(low.dx.isFinite && low.dy.isFinite, "A card maps to finite pixels")
        return SIMD4(
            Float(low.dx),
            Float(low.dy),
            Float(low.dx + frame.size.width * pixels),
            Float(low.dy + frame.size.height * pixels)
        )
    }
}
