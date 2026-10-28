import Geometry
import Model
import QuartzCore
import Testing

@testable import Rendering

/// A canvas renderer and its frame work go away when the canvas lets them go, after frames with
/// a handoff, text, cards, and previews (review M9 section 3.4, item 9, the M10 plan task 3.7).
/// A closure of a Metal handler or of the loader that kept one would keep its textures.
@MainActor
@Suite("Renderer lifetime")
struct RendererLifetimeTests {
    /// The longest wait for the GPU handlers and the loads to end.
    private static let timeout = Duration.seconds(2)

    @Test("A renderer and its frame work go away after their last frame")
    func goesAway() async throws {
        weak var weakRenderer: CanvasRenderer?
        let weakFrames = WeakReference<FrameRenderer>()
        do {
            let source = FakePreviews(data: try FakePreviews.png(width: 300, height: 150))
            let renderer = try CanvasRenderer(
                configuration: RendererConfiguration(),
                previews: source
            )
            weakRenderer = renderer
            renderer.engine.withRenderer { frames in weakFrames.object = frames }
            let layer = CAMetalLayer()
            renderer.configure(layer)
            layer.drawableSize = CGSize(width: 400, height: 240)
            renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
            let frame = Rect(origin: Point(x: -60, y: -40), size: Size(width: 120, height: 80))
            renderer.load([try CardStoreTests.card(1, frame: frame, title: "Tree")])
            renderer.load([try TextRenderingTests.box("node", at: Point(x: 0, y: 60))])
            renderer.load(PerformanceContent.dense(count: 20, points: 60))
            var presented = false
            let stroke = StrokeBuilder.stroke([Point(x: -20, y: 0), Point(x: 20, y: 5)], seed: 999)
            renderer.add([stroke]) { presented = true }
            for _ in 0..<200 {
                _ = renderer.renderFrame(into: layer, deadline: nil)
                try await Task.sleep(for: .milliseconds(1))
                if presented && !renderer.isLoading { break }
            }
            #expect(presented, "The handoff frame was shown")
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.timeout)
        while weakRenderer != nil || weakFrames.object != nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(weakRenderer == nil, "The canvas renderer stays")
        #expect(weakFrames.object == nil, "The frame work stays")
    }
}
