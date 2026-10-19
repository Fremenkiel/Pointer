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
    private let signposter = OSSignposter(subsystem: "dk.saarikivi.pointer", category: "Rendering")
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Rendering")
    /// The committed layer, or `nil` before the first frame with a drawable size.
    private(set) var layer: CommittedLayer?
    private var pendingSlots: [Int] = []
    /// The newest handoff whose strokes wait for the screen, or 0 if none waits.
    private var waitingHandoff: UInt64 = 0
    private var frame: UInt64 = 0
    /// The canvas area of the strokes removed since the last frame, or `nil` (D-66).
    private var dirtyArea: Rect?
    /// `true` after a new viewport until the next frame makes a new committed layer.
    private var needsNewLayer = false
    private var viewSize = Size.zero
    private var displayScale = 1.0
    /// Runs on any thread after the first frame that shows the strokes of a handoff, with the
    /// number of the newest handoff in that frame.
    private let onPresented: @Sendable (UInt64) -> Void

    /// The camera of the canvas.
    var camera = Camera(center: .zero, zoom: Limits.standardZoom)
    /// Gets the command buffer and the drawable of each frame before the commit. Only the tests
    /// set it.
    var onCommit: ((any MTLCommandBuffer, any CAMetalDrawable) -> Void)?

    /// The composite pass of each frame, made once (PERF-01, docs/m2-fix-plan.md, phase 5).
    private let compositePass: MTLRenderPassDescriptor = {
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
        onPresented: @escaping @Sendable (UInt64) -> Void
    ) throws(RenderingError) {
        precondition(configuration.instanceBudgetPerFrame > 0, "The frame budget must be positive")
        precondition(configuration.drawListCapacity > 0, "The draw list must hold entries")
        precondition(configuration.buildTimeBudget > 0, "The build time budget must be positive")
        guard let device = MTLCreateSystemDefaultDevice() else { throw .noDevice }
        resources = try InkResources(device: device)
        self.configuration = configuration
        self.onPresented = onPresented
        let arena = try PointArena(
            device: device,
            initialSlabs: configuration.initialArenaSlabs,
            byteBudget: configuration.arenaByteBudget
        )
        store = StrokeStore(arena: arena)
        let ring = try DrawListRing(device: device, capacity: configuration.drawListCapacity)
        encoder = InkEncoder(resources: resources, store: store, ring: ring)
        pendingSlots.reserveCapacity(Self.pendingCapacity)
    }

    /// `true` if the renderer has work for more frames: a build or a stroke that waits.
    ///
    /// Before the first frame has a texture, the renderer still needs a frame. Otherwise an
    /// early frame without a drawable size ends the frame loop, and the screen stays black.
    var needsMoreFrames: Bool {
        guard let layer, !needsNewLayer else { return viewSize.width > 0 && viewSize.height > 0 }
        return layer.isBuilding || layer.isSettling || !pendingSlots.isEmpty || waitingHandoff > 0
            || dirtyArea != nil
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
        precondition(store.count + strokes.count <= Limits.maxStrokesPerCanvas, "Too many strokes")
        for stroke in strokes {
            store.add(stroke)
        }
        layer?.invalidate()
        assert(store.count >= strokes.count, "The store holds the loaded strokes")
    }

    /// Applies one edit: it removes strokes, notes their area for a redraw in the next frame,
    /// and adds the new strokes (D-66). A removed ID that the store does not hold is ignored.
    ///
    /// - Precondition: The renderer holds room for the added strokes.
    func apply(_ edit: RenderEdit) {
        precondition(
            store.count + edit.added.count <= Limits.maxStrokesPerCanvas + edit.removed.count,
            "Too many strokes"
        )
        for id in edit.removed {
            guard let bounds = store.bounds(of: id) else { continue }
            // The next frame is the first one that can no longer read the stroke.
            store.remove(id, frame: frame + 1)
            dirtyArea = dirtyArea.map { Self.union($0, bounds) } ?? bounds
        }
        for stroke in edit.added {
            pendingSlots.append(store.add(stroke))
        }
        assert(pendingSlots.count >= edit.added.count, "Each new stroke waits for the next frame")
    }

    /// Notes that the edits of handoff number `handoff` wait for the screen.
    ///
    /// - Precondition: `handoff` is positive.
    func markHandoff(_ handoff: UInt64) {
        precondition(handoff > 0, "Handoff numbers start at 1")
        waitingHandoff = max(waitingHandoff, handoff)
    }

    private static func union(_ first: Rect, _ second: Rect) -> Rect {
        Rect(
            minX: min(first.minX, second.minX),
            minY: min(first.minY, second.minY),
            maxX: max(first.maxX, second.maxX),
            maxY: max(first.maxY, second.maxY)
        )
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
        guard let layer = committedLayer(for: drawableSize),
            let commandBuffer = resources.queue.makeCommandBuffer()
        else { return false }
        frame += 1
        store.releaseRemovals(at: frame)
        let context = FrameContext(commandBuffer: commandBuffer, frame: frame)
        encoder.beginFrame(context)
        encodeContent(layer: layer, context: context)
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
        if let area = dirtyArea {
            layer.redraw(area, store: store, encoder: encoder, context: context)
            dirtyArea = nil
        }
        // One pass for all new strokes of the frame, from the reused list (PERF-01).
        layer.addStrokes(pendingSlots, encoder: encoder, context: context)
        pendingSlots.removeAll(keepingCapacity: true)
        _ = layer.startBuildIfNeeded(camera: camera, displayScale: displayScale, store: store)
        layer.continueBuild(
            encoder: encoder,
            context: context,
            budget: configuration.instanceBudgetPerFrame,
            deadline: CACurrentMediaTime() + configuration.buildTimeBudget
        )
        assert(pendingSlots.isEmpty, "Each new stroke reached the committed layer")
        assert(layer.front != nil || layer.isBuilding, "The layer has a front texture or a build")
    }

    private func encodeComposite(
        layer: CommittedLayer,
        commandBuffer: any MTLCommandBuffer,
        texture: any MTLTexture
    ) {
        precondition(
            texture.pixelFormat == InkResources.drawableFormat,
            "Drawable format is not BGRA"
        )
        let pass = compositePass
        pass.colorAttachments[0].texture = texture
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        // The descriptor lives on, so it must not hold the drawable after the frame.
        pass.colorAttachments[0].texture = nil
        guard let encoder else {
            assertionFailure("Metal gave no render encoder for the composite pass")
            return
        }
        #if DEBUG
            // A label costs two allocations per frame and helps only in a GPU capture.
            encoder.label = "Composite"
        #endif
        if let front = layer.shown {
            let size = Size(width: Double(texture.width), height: Double(texture.height))
            encoder.setRenderPipelineState(resources.compositePipeline)
            encoder.setFragmentTexture(front.texture, index: 0)
            encoder.setFragmentValue(
                layer.compositeUniforms(
                    camera: camera,
                    displayScale: displayScale,
                    drawableSize: size
                ),
                index: 0
            )
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }

    /// A new stroke is on the screen when a front texture exists, because the frame drew it into
    /// that texture. Before the first build completes, the handoff waits.
    private func attachHandoff(
        to drawable: any CAMetalDrawable,
        commandBuffer: any MTLCommandBuffer
    ) {
        guard waitingHandoff > 0, layer?.front != nil else { return }
        assert(pendingSlots.isEmpty, "The frame drew each new stroke before the handoff")
        let handoff = waitingHandoff
        waitingHandoff = 0
        assert(handoff > 0, "A handoff number starts at 1")
        let onPresented = onPresented
        #if targetEnvironment(simulator)
            // The simulator has no presented handler. The GPU completion is the closest event.
            commandBuffer.addCompletedHandler { _ in onPresented(handoff) }
        #else
            drawable.addPresentedHandler { _ in onPresented(handoff) }
        #endif
    }
}
