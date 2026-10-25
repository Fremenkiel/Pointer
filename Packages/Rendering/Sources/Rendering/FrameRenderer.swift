import Geometry
import Metal
import Model
import QuartzCore
import os

/// The frame work of the renderer: the stroke store, the committed layer, and the passes of
/// each frame (architecture.md 5.2).
///
/// One thread at a time uses it: the render thread in the app (D-42), or the thread of a test.
/// `RenderEngine` keeps it behind a lock and gives it the changes of the main actor.
final class FrameRenderer {
    let resources: InkResources
    let configuration: RendererConfiguration
    let store: StrokeStore
    let encoder: InkEncoder
    /// The text boxes with their layouts (D-84).
    let texts = TextStore()
    /// The text pass with the glyph atlas (D-29).
    let textEncoder: TextEncoder
    /// The canvas area of the text boxes changed since the last frame, or `nil` (D-82).
    var dirtyTextArea: Rect?
    /// The loads whose layouts run off the render thread (D-92).
    var textLoadsInFlight = 0
    /// The boxes that an edit changed while a load ran. The load skips them, because the edit is
    /// newer.
    var textEditedDuringLoad: Set<TextBoxID> = []
    /// The cards with the layouts of their titles (D-96).
    let cards = CardStore()
    /// The card previews on the GPU, made at the first card (D-97).
    var previews: PreviewAtlas?
    /// The render of the preview of this canvas, made at the first leave (D-97).
    var previewRenderer: PreviewRenderer?
    /// The open or the leave of a card that runs, or `nil` (D-98).
    var transition: FrameTransition?
    /// The frozen copy of the parent frame that a child keeps after its open (D-109).
    var parentImage: InkTarget?
    /// The pinch-out exit that runs, or `nil` (CARD-05).
    var pinchExit: PinchExit?
    /// The flight of the camera that the render thread plays, or `nil` (D-121).
    var flight: RenderFlight?
    private let signposter = OSSignposter(subsystem: "dk.saarikivi.pointer", category: "Rendering")
    let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Rendering")
    /// The committed layer, or `nil` before the first frame with a drawable size.
    private(set) var layer: CommittedLayer?
    /// The new strokes that the next frame draws into the front texture.
    var pendingSlots: [Int] = []
    /// The newest handoff whose strokes wait for the screen, or 0 if none waits.
    var waitingHandoff: UInt64 = 0
    /// `true` if a waiting handoff asks for the GPU end of its frame. Only the tests ask (P-08).
    var waitingCompletion = false
    /// The number of the last frame.
    var frame: UInt64 = 0
    /// The eraser circles of the running gesture (D-66).
    var eraserMask = EraserMask()
    /// `true` while the eraser is the tool. The mask texture exists only then, or while a
    /// gesture still runs or shows (D-78).
    var isEraserReady = false
    /// The canvas area of the strokes removed since the last frame, or `nil` (D-66).
    var dirtyArea: Rect?
    /// `true` after a new viewport until the next frame makes a new committed layer.
    private var needsNewLayer = false
    private(set) var viewSize = Size.zero
    private(set) var displayScale = 1.0
    /// Runs on any thread after the first frame that shows the strokes of a handoff, with the
    /// number of the newest handoff in that frame.
    private let onPresented: @Sendable (UInt64) -> Void
    /// Runs on any thread when the GPU completes the first frame of a handoff, with the number of
    /// the handoff and the `gpuEndTime` of the frame (D-74).
    private let onCompleted: @Sendable (UInt64, Double) -> Void

    /// The camera of the canvas.
    var camera = Camera(center: .zero, zoom: Limits.standardZoom)
    /// Gets the command buffer and the drawable of each frame before the commit. Only the tests
    /// set it.
    var onCommit: ((any MTLCommandBuffer, any CAMetalDrawable) -> Void)?

    /// The composite pass of each frame, made once (PERF-01, docs/m2-fix-plan.md, phase 5).
    let compositePass: MTLRenderPassDescriptor = {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return pass
    }()

    /// The first capacity of the list of strokes that wait for a frame.
    private static let pendingCapacity = 64

    /// Makes the frame work on the system GPU.
    ///
    /// - Precondition: The configuration values are positive.
    /// - Throws: `RenderingError` if the device has no GPU or a Metal object fails.
    init(
        configuration: RendererConfiguration,
        onCompleted: @escaping @Sendable (UInt64, Double) -> Void = { _, _ in },
        onPresented: @escaping @Sendable (UInt64) -> Void
    ) throws(RenderingError) {
        precondition(configuration.instanceBudgetPerFrame > 0, "The frame budget must be positive")
        precondition(configuration.drawListCapacity > 0, "The draw list must hold entries")
        precondition(configuration.buildTimeBudget > 0, "The build time budget must be positive")
        guard let device = MTLCreateSystemDefaultDevice() else { throw .noDevice }
        resources = try InkResources(device: device)
        self.configuration = configuration
        self.onPresented = onPresented
        self.onCompleted = onCompleted
        let arena = try PointArena(
            device: device,
            initialSlabs: configuration.initialArenaSlabs,
            byteBudget: configuration.arenaByteBudget
        )
        store = StrokeStore(arena: arena)
        let ring = try DrawListRing(device: device, capacity: configuration.drawListCapacity)
        encoder = InkEncoder(resources: resources, store: store, ring: ring)
        compositePass.colorAttachments[0].clearColor = Self.clearColor(configuration.background)
        textEncoder = TextEncoder(
            resources: resources,
            store: texts,
            cards: cards,
            atlas: GlyphAtlas(device: device, byteBudget: configuration.glyphAtlasByteBudget),
            ring: try GlyphRing(device: device, capacity: configuration.glyphCapacity),
            borderCoverage: configuration.cardBorderCoverage,
            fillCoverage: configuration.cardFillCoverage
        )
        pendingSlots.reserveCapacity(Self.pendingCapacity)
    }

    /// `true` if the renderer has work for more frames: a build or a stroke that waits.
    ///
    /// Before the first frame has a texture, the renderer still needs a frame. Otherwise an
    /// early frame without a drawable size ends the frame loop, and the screen stays black.
    ///
    /// An open frees the committed layer, so its frames need only the freeze and the previews.
    /// The flight and the inbox wake the frames of the camera and the weight. Without this
    /// rule, the frozen parent drew a frame at each update of the display link until the swap
    /// (review after M9).
    var needsMoreFrames: Bool {
        if let transition, transition.freezes {
            return !transition.isFrozen || !(previews?.pending.isEmpty ?? true)
        }
        guard let layer, !needsNewLayer else { return viewSize.width > 0 && viewSize.height > 0 }
        return layer.isBuilding || layer.isSettling || layer.isRedrawing || !pendingSlots.isEmpty
            || waitingHandoff > 0 || dirtyArea != nil || eraserMask.hasNewSamples
            || layer.isRedrawingText || dirtyTextArea != nil || !(previews?.pending.isEmpty ?? true)
            || previews?.dirtyArea != nil
            || previewRenderer?.job != nil
    }

    /// Sets the size of the view and the display scale. A change rebuilds the committed layer.
    ///
    /// - Precondition: The scale is positive and the size is finite.
    func setViewport(viewSize: Size, displayScale: Double) {
        precondition(displayScale > 0, "Display scale must be positive, got \(displayScale)")
        precondition(viewSize.width.isFinite && viewSize.height.isFinite, "View size is not finite")
        guard viewSize != self.viewSize || displayScale != self.displayScale else { return }
        self.viewSize = viewSize
        self.displayScale = displayScale
        needsNewLayer = true
    }

    /// Adds strokes without a handoff, for example at load time.
    ///
    /// - Precondition: The renderer holds room for the strokes.
    func load(_ strokes: [Stroke]) {
        precondition(
            store.count + strokes.count <= Limits.maxStrokesAfterErase,
            "Too many strokes"
        )
        store.add(contentsOf: strokes)
        layer?.invalidate()
        assert(store.count >= strokes.count, "The store holds the loaded strokes")
    }

    /// Draws one frame. The frame takes the drawable from `drawable` after the content passes,
    /// so it holds the drawable as briefly as possible.
    ///
    /// - Precondition: `drawableSize` is finite.
    /// - Returns: `true` if the renderer needs another frame.
    func renderFrame(
        drawableSize: CGSize,
        deadline: TimeInterval?,
        drawable: DrawableSource
    ) -> Bool {
        precondition(drawableSize.width.isFinite && drawableSize.height.isFinite, "Size not finite")
        precondition(drawableSize.width >= 0 && drawableSize.height >= 0, "Size is negative")
        RenderSignpost.begin("Frame")
        defer { RenderSignpost.end("Frame") }
        if transition?.freezes == true {
            return renderFrozenFrame(drawableSize: drawableSize, drawable: drawable)
        }
        guard let layer = committedLayer(for: drawableSize),
            let commandBuffer = resources.queue.makeCommandBuffer()
        else { return false }
        frame += 1
        store.releaseRemovals(at: frame)
        layer.updateMask(
            isNeeded: isEraserReady || eraserMask.isActive || eraserMask.hasStamps,
            resources: resources
        )
        let context = FrameContext(commandBuffer: commandBuffer, frame: frame)
        encoder.beginFrame(context)
        encodeContent(layer: layer, context: context)
        encodeEraserMask(layer: layer, commandBuffer: commandBuffer)
        RenderSignpost.begin("NextDrawable")
        let target = drawable.next()
        RenderSignpost.end("NextDrawable")
        guard let target else {
            commandBuffer.commit()
            return true
        }
        encodeComposite(layer: layer, commandBuffer: commandBuffer, texture: target.texture)
        attachHandoff(to: target, commandBuffer: commandBuffer)
        commandBuffer.present(target)
        onCommit?(commandBuffer, target)
        commandBuffer.commit()
        if let deadline, CACurrentMediaTime() > deadline {
            signposter.emitEvent("LateFrame")
        }
        return needsMoreFrames
    }

    /// Stamps the new eraser samples into the mask of the front texture.
    private func encodeEraserMask(layer: CommittedLayer, commandBuffer: any MTLCommandBuffer) {
        guard let front = layer.front, let mask = layer.mask else { return }
        eraserMask.encode(
            into: mask,
            front: front,
            resources: resources,
            commandBuffer: commandBuffer
        )
    }

    /// Frees the committed textures and the eraser mask, for an open (D-110). A later frame
    /// without a transition makes new ones.
    func releaseCommittedLayer() {
        layer = nil
        needsNewLayer = true
        assert(layer == nil, "The committed textures go")
    }

    /// A drawable of a new size, for example after a rotation, makes new textures.
    private func committedLayer(for drawableSize: CGSize) -> CommittedLayer? {
        let width = Int(drawableSize.width)
        let height = Int(drawableSize.height)
        assert(width >= 0 && height >= 0, "Drawable size \(width) x \(height) is negative")
        if let layer, !needsNewLayer, layer.drawableWidth == width, layer.drawableHeight == height {
            return layer
        }
        guard width >= 1, height >= 1 else { return nil }
        do {
            layer = try CommittedLayer(
                resources: resources,
                drawableWidth: width,
                drawableHeight: height,
                fallback: layer?.shown
            )
            needsNewLayer = false
        } catch {
            logger.error("Committed layer failed: \(String(describing: error))")
            return nil
        }
        assert(layer != nil, "A committed layer exists after the setup")
        return layer
    }

    private func encodeContent(layer: CommittedLayer, context: FrameContext) {
        // The previews go into the atlas before the passes that sample them.
        uploadPreviews(context)
        // The draw list of the frame is free, so the glyph buffer of the frame is free too.
        textEncoder.beginFrame()
        if let area = dirtyArea {
            layer.redraw(area, store: store, encoder: encoder, context: context)
            dirtyArea = nil
        } else {
            layer.continueRedraw(encoder: encoder, context: context)
        }
        // One pass for the new strokes of the frame, from the reused list (PERF-01). The strokes
        // that do not fit into the draw list wait for the next frame (F-05).
        let drawn = layer.addStrokes(pendingSlots, encoder: encoder, context: context)
        pendingSlots.removeFirst(drawn)
        encodeTextChange(layer: layer, context: context)
        _ = layer.startBuildIfNeeded(
            camera: camera,
            displayScale: displayScale,
            store: store,
            texts: texts,
            cards: cards
        )
        layer.continueBuild(
            encoder: encoder,
            context: context,
            budget: configuration.instanceBudgetPerFrame,
            deadline: CACurrentMediaTime() + configuration.buildTimeBudget,
            text: textEncoder
        )
        continuePreviewRender(context)
        assert(layer.front != nil || layer.isBuilding, "The layer has a front texture or a build")
    }

    /// A new stroke is on the screen when a front texture exists and the frame drew the last
    /// new stroke and the last stroke of a redraw. Before that, the handoff waits, so the live
    /// stroke stays until its ink is in the texture (F-05).
    private func attachHandoff(
        to drawable: any CAMetalDrawable,
        commandBuffer: any MTLCommandBuffer
    ) {
        guard waitingHandoff > 0, let layer, layer.front != nil, pendingSlots.isEmpty,
            !layer.isRedrawing
        else { return }
        let handoff = waitingHandoff
        waitingHandoff = 0
        assert(handoff > 0, "A handoff number starts at 1")
        let onPresented = onPresented
        // The handler and its hop to the main queue run only for a change that asks (P-08).
        if waitingCompletion {
            let onCompleted = onCompleted
            commandBuffer.whenCompleted { buffer in onCompleted(handoff, buffer.gpuEndTime) }
            waitingCompletion = false
        }
        #if targetEnvironment(simulator)
            // The simulator has no presented handler. The GPU completion is the closest event.
            commandBuffer.whenCompleted { _ in onPresented(handoff) }
        #else
            drawable.addPresentedHandler { _ in onPresented(handoff) }
        #endif
    }
}
