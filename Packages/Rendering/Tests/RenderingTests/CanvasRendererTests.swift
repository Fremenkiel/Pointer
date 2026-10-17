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

    @Test("The composite shows the front texture 1:1 when the camera did not move")
    func compositeIdentity() throws {
        let resources = try makeResources()
        let layer = try CommittedLayer(
            resources: resources,
            drawableWidth: 400,
            drawableHeight: 240
        )
        let store = StrokeStore(
            arena: try PointArena(
                device: resources.device,
                initialSlabs: 1,
                byteBudget: 1 << 20
            )
        )
        let camera = Camera(center: Point(x: 5, y: 7), zoom: 2)
        #expect(layer.startBuildIfNeeded(camera: camera, displayScale: 2, store: store))
        let ring = try DrawListRing(device: resources.device, capacity: 4)
        let encoder = InkEncoder(resources: resources, store: store, ring: ring)
        let commandBuffer = try #require(resources.queue.makeCommandBuffer())
        ring.beginFrame(commandBuffer)
        layer.continueBuild(encoder: encoder, commandBuffer: commandBuffer, budget: 10, frame: 1)
        commandBuffer.commit()
        let uniforms = layer.compositeUniforms(
            camera: camera,
            drawableSize: Size(width: 400, height: 240)
        )
        #expect(uniforms.scale == SIMD2(1, 1))
        #expect(uniforms.offset == SIMD2(200, 120))
        let moved = layer.compositeUniforms(
            camera: camera.panned(byView: Vector(dx: 10, dy: 0)),
            drawableSize: Size(width: 400, height: 240)
        )
        #expect(moved.offset == SIMD2(180, 120))
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
        encoder.ring.beginFrame(commandBuffer)
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
        let late = InkPassOptions(clear: true, instanceBudget: .max, frame: 1, deadline: 0)
        let cursor = encoder.encodePass(
            commandBuffer,
            target: target,
            slots: slots,
            cursor: 0,
            options: late
        )
        let rest = InkPassOptions(clear: false, instanceBudget: .max, frame: 1)
        let end = encoder.encodePass(
            commandBuffer,
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
