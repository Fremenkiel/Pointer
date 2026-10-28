import Dispatch
import Geometry
import Metal
import Model

/// Renders the preview of a canvas that is not on the screen, for a card whose preview file is
/// missing (the M6 plan task 3.3, item 6, D-97, D-157).
///
/// The app makes one maker and keeps it, so all previews share one `OffscreenPreview`: a command
/// queue, the shared pipelines, the preview targets, and one glyph atlas, ring, and text encoder
/// (the M10 plan task 3.4). The render blocks until the GPU completes, so the actor runs on its
/// own serial queue, off the main actor, the render thread, and the shared pool, one preview at
/// a time.
public actor PreviewMaker {
    private let queue = DispatchSerialQueue(
        label: "dk.saarikivi.pointer.preview-maker",
        qos: .utility
    )
    private let configuration: RendererConfiguration
    /// The parts of all previews, or `nil` before the first one.
    private var parts: OffscreenPreview?

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

    /// The configuration of the offscreen previews.
    public static var configuration: RendererConfiguration { RendererConfiguration() }

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
        let parts = try madeParts()
        let placement = PreviewRenderer.placement(
            camera: camera,
            cardAspect: cardAspect,
            size: size,
            viewSize: viewSize
        )
        return try parts.render(content, placement: placement)
    }

    /// Returns the parts of the previews, and makes them at the first call.
    private func madeParts() throws(RenderingError) -> OffscreenPreview {
        if let parts { return parts }
        let made = try OffscreenPreview(configuration: configuration)
        parts = made
        return made
    }
}
