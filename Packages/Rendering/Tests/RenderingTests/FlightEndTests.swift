import Geometry
import Metal
import Model
import QuartzCore
import XCTest

@testable import Rendering

/// The end of a flight of the render thread draws no extra frame (m10-plan.md task 5.1). The
/// main thread sends the last camera of a flight again at its end. A frame for it showed nothing
/// new, and after an idle refresh its present counted as the late frame at the end of an open:
/// 4 to 6 in 30 opens before the fix, 0 after.
@MainActor
final class FlightEndTests: XCTestCase {
    func testLastCameraOfAFlightDrawsNoFrame() throws {
        let renderer = try CanvasRenderer()
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        renderer.load(PerformanceContent.dense(count: 20, points: 60))
        for _ in 0..<100 {
            guard renderer.renderFrame(into: layer, deadline: nil) else { break }
        }
        let target = Camera(center: Point(x: 30, y: 10), zoom: 2)
        let start = CACurrentMediaTime()
        let flight = CameraFlight(from: renderer.camera, to: target, duration: 0.05, start: start)
        renderer.fly(RenderFlight(flight: flight, effect: .none, fixedZoom: nil))
        // The frames play the flight past its end.
        for step in 0..<100 {
            let time = start + Double(step) * 0.01
            guard try frame(renderer, layer, deadline: time).needsMore || time < start + 0.06
            else { break }
        }
        // The main thread sends the last camera of the flight, as `applyCamera` does at its end.
        renderer.camera = target
        XCTAssertFalse(try frame(renderer, layer, deadline: nil).didDraw, "The same camera")
        renderer.camera = Camera(center: Point(x: 31, y: 10), zoom: 2)
        XCTAssertTrue(try frame(renderer, layer, deadline: nil).didDraw, "A new camera draws")
    }

    private func frame(
        _ renderer: CanvasRenderer,
        _ layer: CAMetalLayer,
        deadline: TimeInterval?
    ) throws -> FrameOutcome {
        let drawable = try XCTUnwrap(layer.nextDrawable())
        let outcome = renderer.engine.renderFrame(
            drawableSize: layer.drawableSize,
            deadline: deadline,
            drawable: .drawable(drawable)
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        return outcome
    }
}
