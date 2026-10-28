import Geometry
import Model
import QuartzCore
import XCTest

@testable import Rendering

/// The time until the previews of a screen of D-56 cards show at zoom 0.25, with a still camera
/// (D-97). An upload frame takes only previews that lie close together, so that the redraw of
/// their cards stays small (the M10 plan section 6.44). The test records the cost of that limit:
/// the frames and the time until no preview loads.
@MainActor
final class PreviewArrivalPerformanceTests: XCTestCase {
    /// The screen of the iPad Pro 11-inch (M4) in landscape, in points.
    private static let viewSize = Size(width: 1_210, height: 834)
    private static let displayScale = 2.0
    /// One frame at 120 Hz.
    private static let frameInterval = 1.0 / 120
    /// The most frames of one arrival.
    private static let maxFrames = 2_000
    private static let repetitions = 3

    func testArrivalOfAScreenOfPreviews() throws {
        let data = try FakePreviews.png(width: 300, height: 210)
        let cards = try PerformanceContent.cards(count: 5_000)
        var times: [Double] = []
        var frameCounts: [Double] = []
        for _ in 0..<Self.repetitions {
            let arrival = try measureArrival(cards: cards, previews: FakePreviews(data: data))
            times.append(arrival.seconds)
            frameCounts.append(Double(arrival.frames))
        }
        let time = times.sorted()[Self.repetitions / 2]
        let frames = frameCounts.sorted()[Self.repetitions / 2]
        let line = String(
            format: "previews of a screen of cards: %.3f s, %.0f frames",
            time,
            frames
        )
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach(["arrival.s": time, "arrival.frames.count": frames])
    }

    /// The time and the frames from the first frame until no preview loads.
    private struct Arrival {
        let seconds: Double
        let frames: Int
    }

    /// Loads the cards into a new renderer, waits for their layout, and draws frames at 120 Hz
    /// until no preview loads.
    private func measureArrival(cards: [Card], previews: FakePreviews) throws -> Arrival {
        let renderer = try CanvasRenderer(previews: previews)
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(
            width: Self.viewSize.width * Self.displayScale,
            height: Self.viewSize.height * Self.displayScale
        )
        renderer.setViewport(viewSize: Self.viewSize, displayScale: Self.displayScale)
        renderer.load(cards)
        for _ in 0..<5_000 where renderer.isLoadingCards {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        renderer.camera = Camera(center: .zero, zoom: Limits.minZoom)
        let start = CACurrentMediaTime()
        var frames = 0
        while frames < Self.maxFrames {
            let needsMore = renderer.renderFrame(into: layer, deadline: nil)
            frames += 1
            RunLoop.main.run(until: Date(timeIntervalSinceNow: Self.frameInterval))
            guard needsMore || renderer.isLoadingPreviews else { break }
        }
        XCTAssertLessThan(frames, Self.maxFrames, "The previews arrive")
        XCTAssertGreaterThan(previews.readCount, 0, "The renderer read previews")
        return Arrival(seconds: CACurrentMediaTime() - start, frames: frames)
    }
}
