import Geometry
import Metal
import Model
import QuartzCore

/// Draws all finished ink of one canvas with Metal (architecture.md section 5).
///
/// The live pen stroke is not a pass of the renderer: the `PKCanvasView` on top draws it. The
/// renderer receives each finished stroke and calls back after the frame with the stroke is on
/// the screen (the handoff of architecture.md 4.2).
///
/// The frames run on the render thread of `InkView` (D-42). This type is the main-actor side: it
/// sends values to the render thread and never waits for a frame.
@MainActor
public final class CanvasRenderer {
    /// The drawables of the Metal layer (D-41).
    static let drawableCount = 3

    /// The state that the render thread shares.
    let engine: RenderEngine
    /// The values of the renderer.
    let configuration: RendererConfiguration
    private let relay: HandoffRelay
    private var callbacks: [(handoff: UInt64, callback: @MainActor () -> Void)] = []
    private var lastHandoff: UInt64 = 0

    /// The camera of the canvas. A change wakes the frame loop.
    public var camera = Camera(center: .zero, zoom: Limits.standardZoom) {
        didSet {
            guard camera != oldValue else { return }
            let camera = camera
            engine.post { box in
                box.camera = camera
                box.hasNewCamera = true
            }
        }
    }

    /// Makes a renderer on the system GPU.
    ///
    /// - Precondition: The configuration values are positive.
    /// - Throws: `RenderingError` if the device has no GPU or a Metal object fails.
    public init(
        configuration: RendererConfiguration = RendererConfiguration()
    ) throws(RenderingError) {
        let relay = HandoffRelay()
        engine = try RenderEngine(configuration: configuration) { handoff in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { relay.renderer?.deliver(upTo: handoff) }
            }
        }
        self.configuration = configuration
        self.relay = relay
        relay.renderer = self
        assert(relay.renderer === self, "The relay reaches the renderer")
    }

    /// The number of strokes that the renderer held after its last frame.
    public var strokeCount: Int { engine.strokeCount }

    /// `true` if the renderer has work for more frames: a change, a build, or a stroke that
    /// waits.
    public var needsMoreFrames: Bool { engine.needsMoreFrames }

    /// Sets up a `CAMetalLayer` as architecture.md 5.1 requires.
    public func configure(_ metalLayer: CAMetalLayer) {
        metalLayer.device = engine.device
        metalLayer.pixelFormat = InkResources.drawableFormat
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.framebufferOnly = true
        // Three drawables (D-41): with two, `nextDrawable()` blocked the main thread for 16.3 ms
        // in each frame, and a pan ran at 60 Hz (docs/m2-fix-plan.md section 2).
        metalLayer.maximumDrawableCount = Self.drawableCount
        // `false`: the frame presents through the command buffer, so no thread waits for the
        // GPU. With `true`, `waitUntilScheduled` blocked the main thread during a camera glide,
        // and touches arrived late (device trace of 2026-10-17, docs/m2-plan.md).
        metalLayer.presentsWithTransaction = false
        metalLayer.isOpaque = true
        assert(metalLayer.maximumDrawableCount == Self.drawableCount, "The layer keeps 3 drawables")
        assert(metalLayer.colorspace != nil, "The sRGB color space must exist (D-38)")
    }

    /// Sets the size of the view and the display scale. A change rebuilds the committed layer.
    ///
    /// - Precondition: The scale is positive and the size is finite.
    public func setViewport(viewSize: Size, displayScale: Double) {
        precondition(displayScale > 0, "Display scale must be positive, got \(displayScale)")
        precondition(viewSize.width.isFinite && viewSize.height.isFinite, "View size is not finite")
        engine.post { $0.viewport = (viewSize, displayScale) }
    }

    /// Adds strokes without a callback, for example at load time.
    ///
    /// - Precondition: The renderer holds room for the strokes.
    public func load(_ strokes: [Stroke]) {
        precondition(strokes.count <= Limits.maxStrokesPerCanvas, "Too many strokes")
        engine.post { box in
            box.loaded += strokes
            assert(box.loaded.count <= Limits.maxStrokesPerCanvas, "Too many strokes wait")
        }
    }

    /// Adds finished strokes. `onPresented` runs after the first frame that shows them.
    ///
    /// - Precondition: The renderer holds room for the strokes.
    public func add(_ strokes: [Stroke], onPresented: @escaping @MainActor () -> Void) {
        change(removing: [], adding: strokes, onPresented: onPresented)
    }

    /// Removes strokes and adds strokes in one change, for an erase, an undo, or a redo.
    /// `onPresented` runs after the first frame that shows the result.
    ///
    /// The renderer clears the area of the removed strokes in the committed texture and draws the
    /// strokes there again (architecture.md 5.2, D-66). A removed ID that the renderer does not
    /// hold is ignored.
    ///
    /// - Precondition: The renderer holds room for the added strokes.
    public func change(
        removing removed: [StrokeID],
        adding added: [Stroke],
        onPresented: @escaping @MainActor () -> Void
    ) {
        precondition(added.count <= Limits.maxStrokesPerCanvas, "Too many strokes")
        precondition(removed.count <= Limits.maxStrokesPerCanvas, "Too many removed strokes")
        lastHandoff += 1
        let handoff = lastHandoff
        callbacks.append((handoff, onPresented))
        let edit = RenderEdit(removed: removed, added: added)
        engine.post { box in
            box.edits.append(edit)
            box.editHandoff = handoff
        }
        assert(!callbacks.isEmpty, "The change waits for its frame")
    }

    /// Draws one frame into the layer on the main thread. The tests use it instead of the render
    /// thread of `InkView`.
    ///
    /// - Returns: `true` if the renderer needs another frame.
    @discardableResult  // The tests drain the frames in a loop and ignore the last result.
    public func renderFrame(into metalLayer: CAMetalLayer, deadline: TimeInterval?) -> Bool {
        engine.renderFrame(
            drawableSize: metalLayer.drawableSize,
            deadline: deadline,
            drawable: .layer(metalLayer)
        ).needsMore
    }

    /// Renders strokes into an image with the same pipelines as the screen. Tests and the
    /// handoff comparison use it.
    ///
    /// - Precondition: The view size times the scale gives at least one pixel.
    /// - Throws: `RenderingError` if a Metal object fails.
    /// - Returns: The image of the view, black with white ink.
    public func renderImage(
        of strokes: [Stroke],
        camera: Camera,
        viewSize: Size,
        displayScale: Double
    ) throws(RenderingError) -> RenderedImage {
        precondition(displayScale > 0, "Display scale must be positive, got \(displayScale)")
        return try engine.withRenderer { renderer throws(RenderingError) -> RenderedImage in
            try renderer.renderImage(
                of: strokes,
                camera: camera,
                viewSize: viewSize,
                displayScale: displayScale
            )
        }
    }

    /// Runs the callbacks of all handoffs up to `handoff`, in order.
    private func deliver(upTo handoff: UInt64) {
        precondition(handoff <= lastHandoff, "Handoff \(handoff) was never sent")
        let count = callbacks.prefix { $0.handoff <= handoff }.count
        let due = callbacks.prefix(count)
        callbacks.removeFirst(count)
        for entry in due { entry.callback() }
        assert(callbacks.allSatisfy { $0.handoff > handoff }, "A due handoff is still waiting")
    }
}

/// Leads the presented events of the render thread to the renderer on the main actor. The
/// renderer does not exist yet when the engine needs the callback, so the relay holds it.
@MainActor
private final class HandoffRelay {
    weak var renderer: CanvasRenderer?
}
