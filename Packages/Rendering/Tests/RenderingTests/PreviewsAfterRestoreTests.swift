import Foundation
import Geometry
import Model
import XCTest
import os

@testable import Rendering

/// The previews of a screen full of cards right after a restore, which cleared the preview
/// cache, so that each visible card renders offscreen (task 4.3 of docs/m9-plan.md, D-157). The
/// test records the measures and has no budget.
@MainActor
final class PreviewsAfterRestoreTests: XCTestCase {
    /// The cards of a full screen: the D-56 canvas shows about 100 cards at zoom 1, and the
    /// loader asks for one preview at a time.
    private static let cardCount = 100
    /// The strokes of each child: a canvas of handwriting.
    private static let strokesPerChild = 2_000
    private static let pollInterval = Duration.microseconds(250)

    func testPreviewsOfAScreenOfCards() async throws {
        let child = try ExportContent.content(
            strokes: Array(ExportPerformanceTests.d56Strokes().prefix(Self.strokesPerChild)),
            textBoxes: [],
            cards: []
        )
        try await OnScreenCanvas.waitForSteadyMemory()
        let available = os_proc_available_memory()
        var lowest = available
        let isDone = OSAllocatedUnfairLock(initialState: false)
        let clock = ContinuousClock()
        let start = clock.now
        let maker = PreviewMaker()
        let count = Self.cardCount
        let task = Task.detached {
            defer { isDone.withLock { $0 = true } }
            for _ in 0..<count {
                _ = try await maker.render(
                    child,
                    camera: child.openCamera,
                    cardAspect: 100.0 / 70.0,
                    viewSize: Size(width: 1_210, height: 834)
                )
            }
        }
        for _ in 0..<2_400_000 where !isDone.withLock({ $0 }) {
            lowest = min(lowest, os_proc_available_memory())
            try await Task.sleep(for: Self.pollInterval)
        }
        try await task.value
        let seconds = start.duration(to: clock.now) / .seconds(1)
        let peak = Double(available - min(available, lowest)) / 1_048_576
        let line = String(
            format: "previews of %d cards after a restore: %.2f s, %.1f ms each, peak %.0f MB",
            count,
            seconds,
            seconds * 1_000 / Double(count),
            peak
        )
        PerformanceRecord.attach(["previews.s": seconds, "peak.mb": peak], line: line)
    }
}
