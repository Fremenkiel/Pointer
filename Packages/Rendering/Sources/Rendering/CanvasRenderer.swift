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
    private var completions: [(handoff: UInt64, callback: @MainActor (Double) -> Void)] = []
    private var lastHandoff: UInt64 = 0

    /// The camera of the canvas. A change wakes the frame loop.
    public var camera = Camera(center: .zero, zoom: Limits.standardZoom) {
        didSet {
            guard camera != oldValue else { return }
            let camera = camera
            engine.post { box in
                box.camera = camera
                box.hasNewCamera = true
                // A camera from the main thread replaces a flight on the render thread (D-121).
                box.flight = nil
                box.endsFlight = true
            }
        }
    }

    /// Makes a renderer on the system GPU. `previews` gives the stored previews of the child
    /// canvases. Without it, the cards show their borders and titles only (D-97).
    ///
    /// - Precondition: The configuration values are positive.
    /// - Throws: `RenderingError` if the device has no GPU or a Metal object fails.
    public init(
        configuration: RendererConfiguration = RendererConfiguration(),
        previews: (any PreviewSource)? = nil
    ) throws(RenderingError) {
        let relay = HandoffRelay()
        engine = try RenderEngine(
            configuration: configuration,
            previewSource: previews,
            onCompleted: { handoff, time in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        relay.renderer?.deliverCompletions(upTo: handoff, time: time)
                    }
                }
            },
            onPresented: { handoff in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { relay.renderer?.deliver(upTo: handoff) }
                }
            }
        )
        self.configuration = configuration
        self.relay = relay
        relay.renderer = self
        assert(relay.renderer === self, "The relay reaches the renderer")
    }

    /// The number of strokes that the renderer held after its last frame.
    public var strokeCount: Int { engine.strokeCount }

    /// `true` while the text of a load is laid out off the render thread or waits for a frame
    /// (D-92). `needsMoreFrames` does not count it, so the first frame does not wait for it.
    public var isLoadingText: Bool { engine.isLoadingText }

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
        precondition(strokes.count <= Limits.maxStrokesAfterErase, "Too many strokes")
        engine.post { box in
            box.loaded += strokes
            assert(box.loaded.count <= Limits.maxStrokesAfterErase, "Too many strokes wait")
        }
    }

    /// Adds text boxes without a callback, at load time. Their layout runs off the render
    /// thread, so the first frame with the strokes does not wait for it, and the text shows a few
    /// frames later (D-92). An edit of a box during the layout wins over the loaded box.
    ///
    /// - Precondition: The canvas holds at most `Limits.maxNodesPerCanvas` boxes.
    public func load(_ textBoxes: [TextBox]) {
        precondition(textBoxes.count <= Limits.maxNodesPerCanvas, "Too many text boxes")
        guard !textBoxes.isEmpty else { return }
        let engine = engine
        engine.post { $0.textLoadsInFlight += 1 }
        DispatchQueue.global(qos: .userInitiated).async {
            let laidOut = TextStore.layOut(textBoxes)
            engine.post { box in
                box.laidOutText += laidOut
                box.textLoadsInFlight -= 1
                assert(box.textLoadsInFlight >= 0, "A load ends once")
            }
        }
    }

    /// Removes text boxes and adds text boxes in one change: an add, an edit, a move, a delete,
    /// or the hide of a box under the edit view and its show at the end of the edit. An added
    /// box takes the place of the box with the same ID. The renderer clears the text of the old
    /// and the new bounds and draws the text boxes there again (architecture.md 5.4, D-82).
    ///
    /// - Precondition: The change holds at most `Limits.maxNodesPerCanvas` boxes.
    public func changeTextBoxes(removing removed: [TextBoxID], adding added: [TextBox]) {
        precondition(removed.count + added.count <= Limits.maxNodesPerCanvas, "Too many boxes")
        precondition(added.allSatisfy { $0.origin.isFinite }, "A text box origin is not finite")
        let edit = TextEdit(removed: removed, added: added)
        engine.post { box in box.textEdits.append(edit) }
    }

    /// Adds finished strokes. `onPresented` runs after the first frame that shows them.
    ///
    /// - Precondition: The renderer holds room for the strokes.
    public func add(_ strokes: [Stroke], onPresented: @escaping @MainActor () -> Void) {
        change(removing: [], adding: strokes, area: nil, onPresented: onPresented)
    }

    /// Removes strokes and adds strokes in one change, for an erase, an undo, or a redo.
    /// `onPresented` runs after the first frame that shows the result.
    ///
    /// The renderer clears the area of the removed strokes in the committed texture and draws the
    /// strokes there again (architecture.md 5.2, D-66). A removed ID that the renderer does not
    /// hold is ignored.
    ///
    /// With an `area`, the renderer redraws only that area, and the added strokes show only
    /// inside it. The caller must make sure that their ink outside the area is on the screen
    /// already, as for the parts of an erase.
    ///
    /// `onCompleted` runs when the GPU completes the first frame that holds the result, with the
    /// `gpuEndTime` of that frame in the clock of `CACurrentMediaTime()` (D-74).
    ///
    /// - Precondition: The renderer holds room for the added strokes.
    public func change(
        removing removed: [StrokeID],
        adding added: [Stroke],
        area: Rect?,
        onCompleted: (@MainActor (Double) -> Void)? = nil,
        onPresented: @escaping @MainActor () -> Void
    ) {
        precondition(added.count <= Limits.maxStrokesAfterErase, "Too many strokes")
        precondition(removed.count <= Limits.maxStrokesAfterErase, "Too many removed strokes")
        lastHandoff += 1
        let handoff = lastHandoff
        callbacks.append((handoff, onPresented))
        if let onCompleted { completions.append((handoff, onCompleted)) }
        let edit = RenderEdit(removed: removed, added: added, area: area)
        let wantsCompletion = onCompleted != nil
        engine.post { box in
            box.edits.append(edit)
            box.editHandoff = handoff
            box.editsWantCompletion = box.editsWantCompletion || wantsCompletion
        }
        assert(!callbacks.isEmpty, "The change waits for its frame")
    }

    /// Tells the renderer whether the eraser is the tool. The mask texture of the eraser exists
    /// only while it is, so a gesture never waits for its allocation (D-78).
    public func setEraserReady(_ isReady: Bool) {
        engine.post { box in box.eraserReady = isReady }
    }

    /// Starts an eraser gesture. Each sample of the gesture then hides the ink under a circle of
    /// `radius` view points until `endErase()` (D-66).
    ///
    /// - Precondition: `radius` is positive and finite.
    public func beginErase(radius: Double) {
        precondition(radius > 0 && radius.isFinite, "Eraser radius must be positive, got \(radius)")
        engine.post { box in
            // A new start replaces a gesture that no frame ended yet, with its samples.
            box.eraserStart = radius
            box.endsEraser = false
            box.eraserSamples.removeAll(keepingCapacity: true)
            if box.eraserSamples.capacity < Self.eraserSampleCapacity {
                box.eraserSamples.reserveCapacity(Self.eraserSampleCapacity)
            }
            // A frame swaps the two lists, so the spare one needs the room too (M-07).
            if box.spareEraserSamples.capacity < Self.eraserSampleCapacity {
                box.spareEraserSamples.reserveCapacity(Self.eraserSampleCapacity)
            }
        }
    }

    /// Adds one eraser sample in view space. It allocates nothing (PERF-01).
    public func addEraserSample(_ point: Point) {
        guard point.isFinite else { return }
        engine.post { box in box.eraserSamples.append(point) }
    }

    /// Ends the eraser gesture. Call it together with the change of the erase, so that one frame
    /// shows the result and clears the mask (D-66).
    public func endErase() {
        engine.post { box in box.endsEraser = true }
    }

    /// The first capacity of the sample list of the inbox: more samples than one frame gets.
    static let eraserSampleCapacity = 64

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

    /// Renders strokes, text boxes, and cards into an image with the same pipelines as the screen.
    /// Only the tests use it.
    ///
    /// - Precondition: The view size times the scale gives at least one pixel.
    /// - Throws: `RenderingError` if a Metal object fails.
    /// - Returns: The image of the view: white ink and text on the background of the
    ///   configuration.
    public func renderImage(
        of strokes: [Stroke],
        textBoxes: [TextBox] = [],
        cards: [Card] = [],
        camera: Camera,
        viewSize: Size,
        displayScale: Double
    ) throws(RenderingError) -> RenderedImage {
        precondition(displayScale > 0, "Display scale must be positive, got \(displayScale)")
        return try engine.withRenderer { renderer throws(RenderingError) -> RenderedImage in
            try renderer.renderImage(
                of: strokes,
                textBoxes: textBoxes,
                cards: cards,
                camera: camera,
                viewSize: viewSize,
                displayScale: displayScale
            )
        }
    }

    /// Runs the completion callbacks of all handoffs up to `handoff`, in order.
    private func deliverCompletions(upTo handoff: UInt64, time: Double) {
        precondition(handoff <= lastHandoff, "Handoff \(handoff) was never sent")
        let count = completions.prefix { $0.handoff <= handoff }.count
        let due = completions.prefix(count)
        completions.removeFirst(count)
        for entry in due { entry.callback(time) }
        assert(completions.allSatisfy { $0.handoff > handoff }, "A due completion still waits")
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
