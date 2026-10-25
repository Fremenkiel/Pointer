import Geometry
import Model
import XCTest

@testable import Rendering

/// Performance baselines of the content pass (PERF-03, D-172). They are valid on a device only.
@MainActor
final class RenderingPerformanceTests: XCTestCase {
    /// The view of the passes: the 13-inch screen in points.
    private static let viewSize = Size(width: 1376, height: 1032)

    /// A content pass of 20,000 strokes of 300 points at zoom 0.25 (acceptance 2).
    func testContentPassTwentyThousandStrokes() throws {
        let content = PerformanceContent.m2Dense(count: 20_000, points: 300)
        try measurePasses(of: content, count: 5, name: "dense 20k")
    }

    /// A content pass of 200,000 short strokes at zoom 0.25 (acceptance 10).
    func testContentPassTwoHundredThousandStrokes() throws {
        let content = PerformanceContent.m2Dense(count: 200_000, points: 30)
        try measurePasses(of: content, count: 1, name: "dense 200k")
    }

    /// A content pass of 200,000 handwriting strokes of 60 points at zoom 0.25. The dense content
    /// alone hides the costs of real input (docs/m2-fix-plan.md, phase 0).
    func testContentPassTwoHundredThousandHandwritingStrokes() throws {
        let content = PerformanceContent.handwriting(count: 200_000)
        try measurePasses(of: content, count: 1, name: "handwriting 200k")
    }

    /// Renders `content` once to warm up and then `count` times, and records the median time.
    /// The first pass loads the points and builds the pipelines, so it does not count, as in
    /// `XCTestCase.measure`.
    ///
    /// - Throws: The error of a pass, which fails the test.
    private func measurePasses(of content: [Stroke], count: Int, name: String) throws {
        let renderer = try CanvasRenderer()
        let camera = Camera(center: .zero, zoom: Limits.minZoom)
        var times: [Double] = []
        for pass in 0...count {
            let start = ContinuousClock.now
            _ = try renderer.renderImage(
                of: content,
                camera: camera,
                viewSize: Self.viewSize,
                displayScale: 2
            )
            let elapsed = ContinuousClock.now - start
            let parts = elapsed.components
            let milliseconds = Double(parts.seconds) * 1e3 + Double(parts.attoseconds) / 1e15
            if pass > 0 { times.append(milliseconds) }
        }
        let median = try XCTUnwrap(PerformanceRecord.median(times))
        let line = String(format: "%@ content pass: median %.1f ms over %d", name, median, count)
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach(["pass.median.ms": median])
    }
}
