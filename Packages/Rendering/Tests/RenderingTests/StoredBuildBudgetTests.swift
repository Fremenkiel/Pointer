import Geometry
import Metal
import Model
import QuartzCore
import XCTest

@testable import Rendering

/// The stored text builds take the build budget of the configuration (review of 2026-10-28,
/// 3.3.4). An XCTest class, because it draws the D-56 text as the performance tests do.
@MainActor
final class StoredBuildBudgetTests: XCTestCase {
    private static let viewSize = Size(width: 1_210, height: 834)
    private static let displayScale = 2.0
    private static let maxFrames = 600

    func testHalfTheBudgetTakesMoreFrames() throws {
        let content = try PerformanceContent.textBoxes(count: 5_000)
        let frames = try [0.002, 0.001].map { budget in
            try Self.buildFrames(content, budget: budget)
        }
        XCTAssertGreaterThanOrEqual(
            Double(frames[1]),
            1.5 * Double(frames[0]),
            "A budget of 1 ms builds in \(frames[1]) frames, 2 ms in \(frames[0])"
        )
    }

    /// Loads the content and counts the frames of the build at zoom 1 after a pan.
    private static func buildFrames(_ content: [TextBox], budget: Double) throws -> Int {
        var configuration = RendererConfiguration()
        configuration.buildTimeBudget = budget
        let renderer = try CanvasRenderer(configuration: configuration)
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(
            width: viewSize.width * displayScale,
            height: viewSize.height * displayScale
        )
        renderer.setViewport(viewSize: viewSize, displayScale: displayScale)
        renderer.load(content)
        for _ in 0..<2_000 {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            guard renderer.isLoadingText else { break }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        XCTAssertFalse(renderer.isLoadingText, "The text loaded")
        // The first build at zoom 0.25 makes the stored runs of all boxes within the budget of
        // each frame, so its frame count follows the budget.
        renderer.camera = Camera(center: Point(x: 1_000, y: 0), zoom: Limits.minZoom)
        var frames = 0
        while frames < maxFrames {
            let needsMore = renderer.renderFrame(into: layer, deadline: nil)
            frames += 1
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.004))
            guard needsMore else { break }
        }
        XCTAssertLessThan(frames, maxFrames, "The build ends")
        return frames
    }
}
