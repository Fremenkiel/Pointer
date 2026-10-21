import Geometry
import Metal
import Model

/// Renders the preview of a canvas that is not on the screen, for a card whose preview file is
/// missing (m6-plan.md task 3.3, item 6, D-97). It blocks its thread until the GPU completes,
/// so it runs off the main actor and off the render thread, one preview at a time.
public enum PreviewMaker {
    /// Renders the preview of `content`: the child region of `camera`, cut to `cardAspect`, as
    /// `CanvasRenderer.renderPreview` does on the screen.
    ///
    /// - Precondition: `cardAspect` is positive, and `viewSize` is positive.
    /// - Throws: `RenderingError` if a Metal object fails.
    /// - Returns: The image, with `size` pixels on its longer side.
    public static func render(
        _ content: CanvasContent,
        camera: Camera,
        cardAspect: Double,
        viewSize: Size,
        size: Int = PreviewImage.maxSide
    ) throws(RenderingError) -> PreviewImage {
        precondition(cardAspect > 0 && cardAspect.isFinite, "Card aspect \(cardAspect)")
        precondition(viewSize.width > 0 && viewSize.height > 0, "View size \(viewSize)")
        RenderSignpost.begin("PreviewMake")
        defer { RenderSignpost.end("PreviewMake") }
        // The frame work of the image path only: its stores and buffers come with the image.
        let frames = try FrameRenderer(
            configuration: RendererConfiguration(
                initialArenaSlabs: 1,
                drawListCapacity: 1,
                glyphCapacity: 1
            ),
            onPresented: { _ in }
        )
        let placement = PreviewRenderer.placement(
            camera: camera,
            cardAspect: cardAspect,
            size: size,
            viewSize: viewSize
        )
        return try frames.renderPreviewImage(
            strokes: Array(content.strokes.values),
            textBoxes: Array(content.textBoxes.values),
            cards: Array(content.cards.values),
            placement: placement
        )
    }
}
