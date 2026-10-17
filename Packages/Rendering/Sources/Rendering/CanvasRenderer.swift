import Geometry
import Metal
import Model
import QuartzCore
import os

/// Draws all finished ink of one canvas with Metal (architecture.md section 5).
///
/// The live pen stroke is not a pass of the renderer: the `PKCanvasView` on top draws it. The
/// renderer receives each finished stroke and calls back after the frame with the stroke is on
/// the screen (the handoff of architecture.md 4.2).
@MainActor
public final class CanvasRenderer {
    let resources: InkResources
    let configuration: RendererConfiguration
    private let store: StrokeStore
    private let encoder: InkEncoder
    private let signposter = OSSignposter(subsystem: "dk.saarikivi.pointer", category: "Rendering")
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Rendering")
    /// The committed layer, or `nil` before the first frame with a drawable size.
    private(set) var layer: CommittedLayer?
    private var pendingSlots: [Int] = []
    private var pendingCallbacks: [@MainActor () -> Void] = []
    private var frame: UInt64 = 0
    private var viewSize = Size.zero
    private var displayScale = 1.0

    /// The drawables of the Metal layer (D-41).
    static let drawableCount = 3

    /// The camera of the canvas. A change asks for a frame.
    public var camera = Camera(center: .zero, zoom: Limits.standardZoom) {
        didSet { if camera != oldValue { onNeedsFrame?() } }
    }

    /// Called when the renderer needs a frame. `InkView` sets it.
    public var onNeedsFrame: (() -> Void)?

    /// Called with the command buffer of each frame before the commit. Only the performance
    /// tests set it, to read the GPU time of a frame.
    var onCommit: ((any MTLCommandBuffer) -> Void)?

    /// Makes a renderer on the system GPU.
    ///
    /// - Precondition: The configuration values are positive.
    /// - Throws: `RenderingError` if the device has no GPU or a Metal object fails.
    public init(
        configuration: RendererConfiguration = RendererConfiguration()
    ) throws(RenderingError) {
        precondition(configuration.instanceBudgetPerFrame > 0, "The frame budget must be positive")
        precondition(configuration.drawListCapacity > 0, "The draw list must hold entries")
        precondition(configuration.buildTimeBudget > 0, "The build time budget must be positive")
        guard let device = MTLCreateSystemDefaultDevice() else { throw .noDevice }
        resources = try InkResources(device: device)
        self.configuration = configuration
        let arena = try PointArena(
            device: device,
            initialSlabs: configuration.initialArenaSlabs,
            byteBudget: configuration.arenaByteBudget
        )
        store = StrokeStore(arena: arena)
        let ring = try DrawListRing(device: device, capacity: configuration.drawListCapacity)
        encoder = InkEncoder(resources: resources, store: store, ring: ring)
    }

    /// The number of strokes that the renderer holds.
    public var strokeCount: Int { store.count }

    /// `true` if the renderer has work for more frames: a build or a stroke that waits.
    ///
    /// Before the first frame has a texture, the renderer still needs a frame. Otherwise an
    /// early frame without a drawable size ends the frame loop, and the screen stays black.
    public var needsMoreFrames: Bool {
        guard let layer else { return viewSize.width > 0 && viewSize.height > 0 }
        return layer.isBuilding || !pendingSlots.isEmpty || !pendingCallbacks.isEmpty
    }

    /// Sets up a `CAMetalLayer` as architecture.md 5.1 requires.
    public func configure(_ metalLayer: CAMetalLayer) {
        metalLayer.device = resources.device
        metalLayer.pixelFormat = InkResources.drawableFormat
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.framebufferOnly = true
        // Three drawables (D-41): with two, `nextDrawable()` blocked the main thread for 16.3 ms
        // in each frame, and a pan ran at 60 Hz (docs/m2-fix-plan.md section 2).
        metalLayer.maximumDrawableCount = Self.drawableCount
        // `false`: the frame presents through the command buffer, so the main thread never waits
        // for the GPU. With `true`, `waitUntilScheduled` blocked the main thread during a camera
        // glide, and touches arrived late (device trace of 2026-10-17, docs/m2-plan.md).
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
        guard viewSize != self.viewSize || displayScale != self.displayScale else { return }
        self.viewSize = viewSize
        self.displayScale = displayScale
        layer = nil
        onNeedsFrame?()
    }

    /// Adds strokes without a callback, for example at load time.
    ///
    /// - Precondition: The renderer holds room for the strokes.
    public func load(_ strokes: [Stroke]) {
        precondition(store.count + strokes.count <= Limits.maxStrokesPerCanvas, "Too many strokes")
        for stroke in strokes {
            store.add(stroke)
        }
        layer?.invalidate()
        assert(store.count >= strokes.count, "The store holds the loaded strokes")
        onNeedsFrame?()
    }

    /// Adds finished strokes. `onPresented` runs after the first frame that shows them.
    ///
    /// - Precondition: The renderer holds room for the strokes.
    public func add(_ strokes: [Stroke], onPresented: @escaping @MainActor () -> Void) {
        precondition(store.count + strokes.count <= Limits.maxStrokesPerCanvas, "Too many strokes")
        for stroke in strokes {
            pendingSlots.append(store.add(stroke))
        }
        pendingCallbacks.append(onPresented)
        assert(pendingSlots.count >= strokes.count, "Each new stroke waits for the next frame")
        onNeedsFrame?()
    }

    /// Draws one frame into the layer.
    ///
    /// - Returns: `true` if the renderer needs another frame.
    @discardableResult  // InkView reads the result. Tests ignore it.
    public func renderFrame(into metalLayer: CAMetalLayer, deadline: TimeInterval?) -> Bool {
        let state = signposter.beginInterval("Frame")
        defer { signposter.endInterval("Frame", state) }
        guard let layer = committedLayer(for: metalLayer.drawableSize),
            let commandBuffer = resources.queue.makeCommandBuffer()
        else { return false }
        frame += 1
        encoder.ring.beginFrame(commandBuffer)
        addGPUTimeSignpost(to: commandBuffer)
        encodeContent(layer: layer, commandBuffer: commandBuffer)
        let drawableState = signposter.beginInterval("NextDrawable")
        let drawable = metalLayer.nextDrawable()
        signposter.endInterval("NextDrawable", drawableState)
        guard let drawable else {
            commandBuffer.commit()
            return true
        }
        encodeComposite(layer: layer, commandBuffer: commandBuffer, texture: drawable.texture)
        attachCallbacks(to: drawable, commandBuffer: commandBuffer)
        commandBuffer.present(drawable)
        onCommit?(commandBuffer)
        commandBuffer.commit()
        if let deadline, CACurrentMediaTime() > deadline {
            signposter.emitEvent("LateFrame")
        }
        return needsMoreFrames
    }

    /// Emits the GPU time of each frame as a signpost event, for the budget of D-28 and the
    /// performance tests (PERF-03).
    private func addGPUTimeSignpost(to commandBuffer: any MTLCommandBuffer) {
        let signposter = signposter
        commandBuffer.addCompletedHandler { buffer in
            let milliseconds = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            signposter.emitEvent("GPUFrame", "\(milliseconds, format: .fixed(precision: 2)) ms")
        }
    }

    private func committedLayer(for drawableSize: CGSize) -> CommittedLayer? {
        if let layer { return layer }
        guard drawableSize.width >= 1, drawableSize.height >= 1 else { return nil }
        do {
            layer = try CommittedLayer(
                resources: resources,
                drawableWidth: Int(drawableSize.width),
                drawableHeight: Int(drawableSize.height)
            )
        } catch {
            logger.error("Committed layer failed: \(String(describing: error))")
            return nil
        }
        assert(layer != nil, "A committed layer exists after the setup")
        return layer
    }

    private func encodeContent(layer: CommittedLayer, commandBuffer: any MTLCommandBuffer) {
        for slot in pendingSlots {
            layer.addStroke(slot, encoder: encoder, commandBuffer: commandBuffer, frame: frame)
        }
        pendingSlots.removeAll(keepingCapacity: true)
        _ = layer.startBuildIfNeeded(camera: camera, displayScale: displayScale, store: store)
        layer.continueBuild(
            encoder: encoder,
            commandBuffer: commandBuffer,
            budget: configuration.instanceBudgetPerFrame,
            frame: frame,
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
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            assertionFailure("Metal gave no render encoder for the composite pass")
            return
        }
        encoder.label = "Composite"
        if let front = layer.front {
            let size = Size(width: Double(texture.width), height: Double(texture.height))
            encoder.setRenderPipelineState(resources.compositePipeline)
            encoder.setFragmentTexture(front.texture, index: 0)
            encoder.setFragmentValue(
                layer.compositeUniforms(camera: camera, drawableSize: size),
                index: 0
            )
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }

    /// A new stroke is on the screen when a front texture exists, because the frame drew it into
    /// that texture. Before the first build completes, the callbacks wait.
    private func attachCallbacks(
        to drawable: any CAMetalDrawable,
        commandBuffer: any MTLCommandBuffer
    ) {
        guard !pendingCallbacks.isEmpty, layer?.front != nil else { return }
        assert(pendingSlots.isEmpty, "The frame drew each new stroke before the callbacks")
        let callbacks = pendingCallbacks
        pendingCallbacks.removeAll(keepingCapacity: true)
        assert(!callbacks.isEmpty, "The frame delivers the waiting callbacks")
        let deliver: @Sendable () -> Void = {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for callback in callbacks { callback() }
                }
            }
        }
        #if targetEnvironment(simulator)
            // The simulator has no presented handler. The GPU completion is the closest event.
            commandBuffer.addCompletedHandler { _ in deliver() }
        #else
            drawable.addPresentedHandler { _ in deliver() }
        #endif
    }
}
