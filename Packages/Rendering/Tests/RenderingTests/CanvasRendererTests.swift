import Geometry
import Metal
import Model
import QuartzCore
import Testing

@testable import Rendering

@MainActor
@Suite("Canvas renderer frame loop")
struct CanvasRendererTests {
    private func makeLayer(renderer: CanvasRenderer) -> CAMetalLayer {
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return layer
    }

    private func drain(_ renderer: CanvasRenderer, layer: CAMetalLayer) -> Int {
        var frames = 0
        for _ in 0..<100 {
            frames += 1
            if !renderer.renderFrame(into: layer, deadline: nil) { break }
        }
        return frames
    }

    @Test("The layer uses the color setup of D-38 and three drawables (D-41)")
    func layerSetup() throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        #expect(layer.pixelFormat == .bgra8Unorm)
        #expect(layer.colorspace?.name == CGColorSpace.sRGB)
        #expect(layer.maximumDrawableCount == CanvasRenderer.drawableCount)
        #expect(!layer.presentsWithTransaction)
    }

    @Test("A handoff calls back after the frame that shows the stroke")
    func handoffCallback() async throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        _ = drain(renderer, layer: layer)
        var presented = false
        renderer.add([StrokeBuilder.curve(at: Point(x: -60, y: 0))]) { presented = true }
        #expect(renderer.needsMoreFrames)
        _ = drain(renderer, layer: layer)
        for _ in 0..<200 where !presented {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(presented)
        #expect(renderer.strokeCount == 1)
        #expect(!renderer.needsMoreFrames)
    }

    @Test("Several strokes of one handoff reach the screen in one frame with one callback")
    func handoffOfSeveralStrokes() async throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        _ = drain(renderer, layer: layer)
        var calls = 0
        let strokes = (0..<3).map {
            StrokeBuilder.curve(at: Point(x: -60, y: Double($0) * 10), seed: $0)
        }
        renderer.add(strokes) { calls += 1 }
        _ = drain(renderer, layer: layer)
        for _ in 0..<200 where calls == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(calls == 1)
        #expect(renderer.strokeCount == 3)
    }

    @Test("After a new viewport, the old texture stays on the screen until the new one is complete")
    func viewportFallback() throws {
        let renderer = try CanvasRenderer(
            configuration: RendererConfiguration(instanceBudgetPerFrame: 100)
        )
        let layer = makeLayer(renderer: renderer)
        let strokes = (0..<20).map {
            StrokeBuilder.curve(at: Point(x: -60, y: Double($0) * 3 - 30), seed: $0)
        }
        renderer.load(strokes)
        _ = drain(renderer, layer: layer)
        layer.drawableSize = CGSize(width: 240, height: 400)
        renderer.setViewport(viewSize: Size(width: 120, height: 200), displayScale: 2)
        renderer.renderFrame(into: layer, deadline: nil)
        let isBuilding = renderer.engine.withRenderer { $0.layer?.front == nil }
        let showsOld = renderer.engine.withRenderer { $0.layer?.shown != nil }
        #expect(isBuilding)
        #expect(showsOld)
        _ = drain(renderer, layer: layer)
        let hasFallback = renderer.engine.withRenderer { $0.layer?.fallback != nil }
        #expect(!hasFallback)
    }

    @Test("A build in chunks completes and stops asking for frames")
    func chunkedBuild() throws {
        let renderer = try CanvasRenderer(
            configuration: RendererConfiguration(instanceBudgetPerFrame: 100)
        )
        let layer = makeLayer(renderer: renderer)
        let strokes = (0..<20).map {
            StrokeBuilder.curve(at: Point(x: -60, y: Double($0) * 3 - 30), seed: $0)
        }
        renderer.load(strokes)
        let frames = drain(renderer, layer: layer)
        #expect(frames > 2)
        #expect(frames < 100)
        renderer.camera = Camera(center: Point(x: 10, y: 0), zoom: 2)
        #expect(renderer.needsMoreFrames == false)
        #expect(drain(renderer, layer: layer) > 1)
    }

    @Test("The composite shows the front texture 1:1 at whole-pixel offsets when the zoom is equal")
    func compositeIdentity() throws {
        let camera = Camera(center: Point(x: 5, y: 7), zoom: 2)
        let layer = try makeBuiltLayer(camera: camera)
        let uniforms = layer.compositeUniforms(
            camera: camera,
            displayScale: 2,
            drawableSize: Size(width: 400, height: 240),
            background: Self.background
        )
        #expect(uniforms.scale == SIMD2(1, 1))
        #expect(uniforms.offset == SIMD2(200, 120))
        let moved = layer.compositeUniforms(
            camera: camera.panned(byView: Vector(dx: 10, dy: 0)),
            displayScale: 2,
            drawableSize: Size(width: 400, height: 240),
            background: Self.background
        )
        #expect(moved.offset == SIMD2(180, 120))
        let fraction = layer.compositeUniforms(
            camera: camera.panned(byView: Vector(dx: 0.3, dy: -0.2)),
            displayScale: 2,
            drawableSize: Size(width: 400, height: 240),
            background: Self.background
        )
        #expect(fraction.offset == SIMD2(199, 120))
        #expect(uniforms.background == SIMD4(Self.background, 1))
    }

    /// The canvas color of CAN-01 in sRGB (D-106).
    private static let background = SIMD3<Float>(41, 44, 51) / 255

    /// Returns a layer of 400 x 240 pixels with a complete, empty build for `camera`.
    private func makeBuiltLayer(camera: Camera) throws -> CommittedLayer {
        let resources = try makeResources()
        let layer = try CommittedLayer(
            resources: resources,
            drawableWidth: 400,
            drawableHeight: 240
        )
        let arena = try PointArena(device: resources.device, initialSlabs: 1, byteBudget: 1 << 20)
        let store = StrokeStore(arena: arena)
        #expect(layer.startBuildIfNeeded(camera: camera, displayScale: 2, store: store))
        let ring = try DrawListRing(device: resources.device, capacity: 4)
        let encoder = InkEncoder(resources: resources, store: store, ring: ring)
        let commandBuffer = try #require(resources.queue.makeCommandBuffer())
        let context = FrameContext(commandBuffer: commandBuffer, frame: 1)
        encoder.beginFrame(context)
        layer.continueBuild(encoder: encoder, context: context, budget: 10)
        commandBuffer.commit()
        return layer
    }

    private func makeResources() throws -> InkResources {
        try InkResources(device: try #require(MTLCreateSystemDefaultDevice()))
    }

    private func makeEncoder(
        _ resources: InkResources,
        strokes: Int
    ) throws -> (InkEncoder, [Int]) {
        let device = resources.device
        let arena = try PointArena(device: device, initialSlabs: 1, byteBudget: 1 << 20)
        let store = StrokeStore(arena: arena)
        let slots = (0..<strokes).map {
            store.add(StrokeBuilder.curve(at: Point(x: 0, y: Double($0)), seed: $0))
        }
        let ring = try DrawListRing(device: device, capacity: 128)
        return (InkEncoder(resources: resources, store: store, ring: ring), slots)
    }

    @Test("A pass past its deadline stops after the first strokes")
    func deadline() throws {
        let resources = try makeResources()
        let (encoder, slots) = try makeEncoder(resources, strokes: 100)
        let commandBuffer = try #require(resources.queue.makeCommandBuffer())
        let context = FrameContext(commandBuffer: commandBuffer, frame: 1)
        encoder.beginFrame(context)
        let texture = try resources.makeTarget(
            width: 64,
            height: 64,
            format: InkResources.committedFormat
        )
        let target = InkTarget(
            texture: texture,
            camera: Camera(center: .zero, zoom: 1),
            displayScale: 1
        )
        let late = InkPassOptions(clear: true, instanceBudget: .max, deadline: 0)
        let cursor = encoder.encodePass(
            context,
            target: target,
            slots: slots,
            cursor: 0,
            options: late
        )
        let rest = InkPassOptions(clear: false, instanceBudget: .max)
        let end = encoder.encodePass(
            context,
            target: target,
            slots: slots,
            cursor: cursor,
            options: rest
        )
        commandBuffer.commit()
        #expect(cursor == InkEncoder.deadlineCheckInterval)
        #expect(end == slots.count)
    }
}
