import Geometry
import Metal
import Model
import QuartzCore
import Testing

@testable import Rendering

/// The frames with a draw list of 4 entries: more strokes than one frame holds go on in the next
/// frames, and nothing traps (F-04, F-05 of docs/m4-fix-plan.md). The drawable has 400 x 240
/// pixels at scale 2, so the texture shows 400 x 240 canvas points at zoom 1.
@MainActor
@Suite("A full draw list")
struct DrawListOverflowTests {
    /// The draw-list entries of each frame.
    private static let capacity = 4
    /// The frames that a test may draw until the renderer needs no more.
    private static let maxFrames = 200
    private static let camera = Camera(center: .zero, zoom: 1)

    /// 40 horizontal lines of one block each.
    private static let lines = (0..<40).map { index in
        StrokeBuilder.stroke(
            (0...40).map { Point(x: Double($0) * 4 - 80, y: Double(index) * 2.5 - 50) },
            seed: index + 1
        )
    }

    /// One block that crosses the strip y -1...1 seven times, so its clipped draw has 7 entries.
    private static let zigzag = StrokeBuilder.stroke(
        (0..<48).map { Point(x: Double($0) * 2 - 48, y: ($0 / 6).isMultiple(of: 2) ? 20 : -20) },
        seed: 99
    )

    @Test("40 new strokes in a handoff all reach the texture, and the handoff waits for them")
    func handoff() async throws {
        let (renderer, layer) = try Self.makeRenderer(capacity: Self.capacity)
        Self.drain(renderer, layer)
        var isPresented = false
        renderer.add(Self.lines) { isPresented = true }
        Self.drain(renderer, layer)
        // The presented event of the last frame arrives after the frames.
        for _ in 0..<Self.maxFrames where !isPresented {
            try await Task.sleep(for: .milliseconds(10))
        }
        let expected = try Self.coverage(of: Self.lines)
        #expect(CoverageReader.largestDifference(try Self.frontCoverage(renderer), expected) <= 1)
        #expect(isPresented)
    }

    @Test("A redraw of 40 strokes draws all of them again in the next frames")
    func redraw() throws {
        let (renderer, layer) = try Self.makeRenderer(capacity: Self.capacity)
        renderer.load(Self.lines)
        Self.drain(renderer, layer)
        renderer.change(
            removing: [],
            adding: [],
            area: Rect(minX: -100, minY: -60, maxX: 100, maxY: 60),
            onPresented: {}
        )
        Self.drain(renderer, layer)
        let expected = try Self.coverage(of: Self.lines)
        #expect(CoverageReader.largestDifference(try Self.frontCoverage(renderer), expected) <= 1)
    }

    @Test("A clipped stroke with more entries than the draw list holds is drawn")
    func clippedStroke() throws {
        let (renderer, layer) = try Self.makeRenderer(capacity: Self.capacity)
        renderer.load([Self.zigzag])
        Self.drain(renderer, layer)
        renderer.change(
            removing: [],
            adding: [],
            area: Rect(minX: -100, minY: -1, maxX: 100, maxY: 1),
            onPresented: {}
        )
        Self.drain(renderer, layer)
        let expected = try Self.coverage(of: [Self.zigzag])
        #expect(CoverageReader.largestDifference(try Self.frontCoverage(renderer), expected) <= 1)
    }

    private static func makeRenderer(capacity: Int) throws -> (CanvasRenderer, CAMetalLayer) {
        let renderer = try CanvasRenderer(
            configuration: RendererConfiguration(drawListCapacity: capacity)
        )
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        renderer.camera = camera
        return (renderer, layer)
    }

    /// Draws frames until the renderer needs no more, and lets the callbacks run.
    private static func drain(_ renderer: CanvasRenderer, _ layer: CAMetalLayer) {
        for _ in 0..<maxFrames where renderer.renderFrame(into: layer, deadline: nil) {}
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    /// Returns the coverage of the front texture after a build with a large draw list.
    private static func coverage(of strokes: [Stroke]) throws -> [UInt8] {
        let (renderer, layer) = try makeRenderer(capacity: RendererConfiguration().drawListCapacity)
        renderer.load(strokes)
        drain(renderer, layer)
        return try frontCoverage(renderer)
    }

    /// Returns the coverage of the front texture once the GPU completes the frames before.
    private static func frontCoverage(_ renderer: CanvasRenderer) throws -> [UInt8] {
        let pixels = try renderer.engine.withRenderer { frameRenderer throws -> [UInt8]? in
            guard let texture = frameRenderer.layer?.front?.texture else { return nil }
            let resources = frameRenderer.resources
            let copy = try resources.makeTarget(
                width: texture.width,
                height: texture.height,
                format: InkResources.committedFormat,
                isReadable: true
            )
            guard let commandBuffer = resources.queue.makeCommandBuffer(),
                let blit = commandBuffer.makeBlitCommandEncoder()
            else { return nil }
            blit.copy(from: texture, to: copy)
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            return CoverageReader.pixels(of: copy)
        }
        return try #require(pixels, "The renderer has no front texture")
    }
}
