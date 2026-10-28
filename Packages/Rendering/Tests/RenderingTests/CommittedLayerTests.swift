import Geometry
import Metal
import Testing

@testable import Rendering

/// The rebuild policy of the M2 fix plan, phase 2. The drawable has 400 x 240 pixels at
/// scale 2, so the texture has a margin of 100 canvas points on the left and the right at zoom 1.
@MainActor
@Suite("Committed layer rebuild policy")
struct CommittedLayerTests {
    private let start = Camera(center: .zero, zoom: 1)

    private struct Subject {
        let layer: CommittedLayer
        let store: StrokeStore
        let encoder: InkEncoder
        let resources: InkResources
    }

    private func makeSubject() throws -> Subject {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let resources = try InkResources(device: device)
        let layer = try CommittedLayer(
            resources: resources,
            drawableWidth: 400,
            drawableHeight: 240
        )
        let arena = try PointArena(device: device, initialSlabs: 1, byteBudget: 1 << 20)
        let store = StrokeStore(arena: arena)
        let ring = try DrawListRing(device: device, capacity: 4)
        let encoder = InkEncoder(resources: resources, store: store, ring: ring)
        let subject = Subject(layer: layer, store: store, encoder: encoder, resources: resources)
        #expect(try frame(subject, camera: start))
        return subject
    }

    /// Runs one frame of the layer and returns `true` if a build started.
    private func frame(_ subject: Subject, camera: Camera) throws -> Bool {
        let started = subject.layer.startBuildIfNeeded(
            camera: camera,
            displayScale: 2,
            store: subject.store
        )
        let commandBuffer = try #require(subject.resources.queue.makeCommandBuffer())
        let context = FrameContext(commandBuffer: commandBuffer, frame: 1)
        subject.encoder.beginFrame(context)
        subject.layer.continueBuild(encoder: subject.encoder, context: context, budget: 1_000)
        commandBuffer.commit()
        return started
    }

    private func panned(by points: Double) -> Camera {
        Camera(center: Point(x: points, y: 0), zoom: 1)
    }

    @Test("A pan inside three quarters of the margin keeps the front texture")
    func smallPan() throws {
        let subject = try makeSubject()
        #expect(try !frame(subject, camera: panned(by: 70)))
        #expect(subject.layer.isSettling)
    }

    @Test("A pan past three quarters of the margin starts a build")
    func largePan() throws {
        let subject = try makeSubject()
        #expect(try frame(subject, camera: panned(by: 80)))
    }

    @Test("A zoom inside the band keeps the texture, and a zoom outside starts a build")
    func zoomBand() throws {
        let subject = try makeSubject()
        #expect(try !frame(subject, camera: Camera(center: .zero, zoom: 0.85)))
        #expect(try frame(subject, camera: Camera(center: .zero, zoom: 0.79)))
    }

    @Test("A camera that stays still for 6 frames gets an exact build")
    func stillCamera() throws {
        let subject = try makeSubject()
        let camera = panned(by: 10)
        for _ in 0..<CommittedLayer.stillFramesBeforeExactBuild {
            #expect(try !frame(subject, camera: camera))
        }
        #expect(try frame(subject, camera: camera))
        #expect(!subject.layer.isSettling)
    }

    @Test("A load starts a build at the same camera")
    func load() throws {
        let subject = try makeSubject()
        #expect(try !frame(subject, camera: start))
        subject.layer.invalidate()
        #expect(try frame(subject, camera: start))
    }
}
