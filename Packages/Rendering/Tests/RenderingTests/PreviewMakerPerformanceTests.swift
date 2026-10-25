import Foundation
import Geometry
import Metal
import Model
import XCTest
import os

@testable import Rendering

/// The time and the peak memory growth of the offscreen preview of a child canvas without a
/// preview file (D-97, PERF-03). The test records the measures and does not fail on them.
@MainActor
final class PreviewMakerPerformanceTests: XCTestCase {
    /// The time between two reads of the available memory, as in `ExportPerformanceTests`.
    private static let pollInterval = Duration.microseconds(250)

    func testPreviewOfD56Canvas() async throws {
        let content = try ExportContent.content(
            strokes: ExportPerformanceTests.d56Strokes(),
            textBoxes: ExportPerformanceTests.textBoxes(count: 5_000),
            cards: ExportPerformanceTests.cards(count: 5_000)
        )
        // The app keeps one maker, so the second preview shows the cost without the Metal setup.
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let before = device.currentAllocatedSize
        let maker = PreviewMaker()
        try await measure(content, name: "D-56, first of a maker", maker: maker)
        try await measure(content, name: "D-56, second of the maker", maker: maker)
        // The Metal memory that the maker keeps between previews (m10-plan.md task 3.4).
        let kept = Double(device.currentAllocatedSize - min(before, device.currentAllocatedSize))
        let megabytes = kept / 1_048_576
        let line = String(format: "Metal memory that the maker keeps: %.1f MB", megabytes)
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach(["kept.mb": megabytes])
        withExtendedLifetime(maker) {}
    }

    /// Renders the preview in a detached task and records the time and the memory growth.
    private func measure(
        _ content: CanvasContent,
        name: String,
        maker: PreviewMaker
    ) async throws {
        try await OnScreenCanvas.waitForSteadyMemory()
        let available = os_proc_available_memory()
        var lowest = available
        let clock = ContinuousClock()
        let start = clock.now
        let isDone = OSAllocatedUnfairLock(initialState: false)
        let task = Task.detached {
            defer { isDone.withLock { $0 = true } }
            return try await maker.render(
                content,
                camera: content.openCamera,
                cardAspect: 4.0 / 3.0,
                viewSize: Size(width: 1_210, height: 834)
            )
        }
        // The bound covers a render of 10 minutes at the poll interval (FLOW-03).
        for _ in 0..<2_400_000 where !isDone.withLock({ $0 }) {
            lowest = min(lowest, os_proc_available_memory())
            try await Task.sleep(for: Self.pollInterval)
        }
        let image = try await task.value
        let seconds = start.duration(to: clock.now) / .seconds(1)
        XCTAssertGreaterThan(image.width, 0)
        let megabytes = Double(available - min(available, lowest)) / 1_048_576
        let line = String(
            format: "preview of %@: %.3f s, peak memory growth %.0f MB",
            name,
            seconds,
            megabytes
        )
        XCTContext.runActivity(named: line) { _ in }
        let key = name.contains("second") ? "second" : "first"
        PerformanceRecord.attach(["\(key).s": seconds, "\(key)-peak.mb": megabytes])
    }
}
