import Dispatch
import Geometry
import Metal
import Model

/// Renders the preview of a canvas that is not on the screen, for a card whose preview file is
/// missing (m6-plan.md task 3.3, item 6, D-97, D-157).
///
/// The app makes one maker and keeps it, so all previews share one `InkResources`: a command
/// queue, the library, and the pipelines. The render blocks until the GPU completes, so the
/// actor runs on its own serial queue, off the main actor, the render thread, and the shared
/// pool, one preview at a time.
public actor PreviewMaker {
    private let queue = DispatchSerialQueue(
        label: "dk.saarikivi.pointer.preview-maker",
        qos: .utility
    )
    private let configuration: RendererConfiguration
    /// The renderer of all previews, or `nil` before the first one.
    private var frames: FrameRenderer?

    /// The executor of the maker: its own serial queue.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Makes a maker. The first render makes the Metal objects.
    ///
    /// - Precondition: The arena budget of the previews holds the longest stroke.
    public init(configuration: RendererConfiguration = PreviewMaker.configuration) {
        precondition(
            configuration.previewArenaByteBudget >= PreviewPasses.minimumByteBudget,
            "The preview arena of \(configuration.previewArenaByteBudget) bytes is too small"
        )
        self.configuration = configuration
    }

    /// The configuration of the offscreen renderer: the frame work of the image path only.
    public static var configuration: RendererConfiguration {
        RendererConfiguration(initialArenaSlabs: 1, drawListCapacity: 1, glyphCapacity: 1)
    }

    /// Renders the preview of `content`: the child region of `camera`, cut to `cardAspect`, as
    /// `CanvasRenderer.renderPreview` does on the screen. Only the items in the region draw.
    ///
    /// - Precondition: `cardAspect` is positive, and `viewSize` is positive.
    /// - Throws: `RenderingError` if a Metal object fails.
    /// - Returns: The image, with `size` pixels on its longer side.
    public func render(
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
        let frames = try madeFrames()
        let placement = PreviewRenderer.placement(
            camera: camera,
            cardAspect: cardAspect,
            size: size,
            viewSize: viewSize
        )
        return try frames.renderPreviewImage(of: content, placement: placement)
    }

    /// Returns the renderer of the previews, and makes it at the first call.
    private func madeFrames() throws(RenderingError) -> FrameRenderer {
        if let frames { return frames }
        let made = try FrameRenderer(configuration: configuration, onPresented: { _ in })
        frames = made
        return made
    }
}
