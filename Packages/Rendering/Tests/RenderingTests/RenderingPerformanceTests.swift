import Geometry
import Model
import XCTest

@testable import Rendering

/// Performance baselines of the content pass (PERF-03). They are valid on a device only. The
/// simulator runs them so that they stay compilable.
@MainActor
final class RenderingPerformanceTests: XCTestCase {
    /// A content pass of 20,000 strokes of 300 points at zoom 0.25 (acceptance 2).
    func testContentPassTwentyThousandStrokes() throws {
        let renderer = try CanvasRenderer()
        let content = PerformanceContent.m2Dense(count: 20_000, points: 300)
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
        let content = PerformanceContent.m2Dense(count: 200_000, points: 30)
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

    /// A content pass of 200,000 handwriting strokes of 60 points at zoom 0.25. The dense content
    /// alone hides the costs of real input (docs/m2-fix-plan.md, phase 0).
    func testContentPassTwoHundredThousandHandwritingStrokes() throws {
        let renderer = try CanvasRenderer()
        let content = PerformanceContent.handwriting(count: 200_000)
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
