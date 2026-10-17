import Geometry
import Model
import XCTest

@testable import Rendering

/// Performance baselines of the content pass (PERF-03). They are valid on a device only. The
/// simulator runs them so that they stay compilable.
@MainActor
final class RenderingPerformanceTests: XCTestCase {
    private func strokes(count: Int, pointsPerStroke: Int) -> [Stroke] {
        (0..<count).map { index in
            let column = Double(index % 200)
            let row = Double(index / 200)
            let origin = Point(x: column * 30 - 3000, y: row * 30 - 1500)
            let points = (0..<pointsPerStroke).map { step in
                Point(x: origin.x + Double(step) * 0.08, y: origin.y + sin(Double(step) * 0.2) * 4)
            }
            return StrokeBuilder.stroke(points, seed: UInt8(truncatingIfNeeded: index))
        }
    }

    /// A content pass of 20,000 strokes of 300 points at zoom 0.25 (acceptance 2).
    func testContentPassTwentyThousandStrokes() throws {
        let renderer = try CanvasRenderer()
        let content = strokes(count: 20_000, pointsPerStroke: 300)
        let camera = Camera(center: .zero, zoom: Limits.minZoom)
        measure(metrics: [XCTClockMetric()]) {
            _ = try? renderer.renderImage(
                of: content,
                camera: camera,
                viewSize: Size(width: 1376, height: 1032),
                displayScale: 2
            )
        }
    }

    /// A content pass of 200,000 short strokes at zoom 0.25 (acceptance 10).
    func testContentPassTwoHundredThousandStrokes() throws {
        let renderer = try CanvasRenderer()
        let content = strokes(count: 200_000, pointsPerStroke: 30)
        let camera = Camera(center: .zero, zoom: Limits.minZoom)
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = try? renderer.renderImage(
                of: content,
                camera: camera,
                viewSize: Size(width: 1376, height: 1032),
                displayScale: 2
            )
        }
    }
}
