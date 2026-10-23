import Export
import Foundation
import Geometry
import Model
import XCTest
import os

/// The time, the peak memory growth, and the size of an export of large canvases (M8 task 2.7,
/// PERF-03). No budget exists yet, so the tests record the measures only (D-144).
///
/// Each test exports once. The memory of the export goes back to the allocator of the process,
/// not to the system, so a second export in the same test shows too little growth.
@MainActor
final class ExportPerformanceTests: XCTestCase {
    /// The time between two reads of the available memory during an export.
    private static let pollInterval = Duration.milliseconds(2)

    /// The content of D-56: 20,000 strokes of 300 points, 5,000 cards, and 5,000 text boxes of
    /// 200 characters, as `D56Library` stores it.
    func testExportOfD56Canvas() async throws {
        let content = try ExportContent.content(
            strokes: Self.d56Strokes(),
            textBoxes: Self.textBoxes(count: 5_000),
            cards: Self.cards(count: 5_000)
        )
        try await measure(content, name: "D-56: 20,000 strokes, 5,000 cards, 5,000 text boxes")
    }

    /// The strokes of D-56 and the largest number of text boxes of a canvas, 10,000.
    func testExportOfD56StrokesAndTenThousandTextBoxes() async throws {
        let content = try ExportContent.content(
            strokes: Self.d56Strokes(),
            textBoxes: Self.textBoxes(count: Limits.maxNodesPerCanvas)
        )
        try await measure(content, name: "20,000 strokes, 10,000 text boxes")
    }

    /// The 200,000 handwriting strokes of `FrameLoopTests`.
    func testExportOfTwoHundredThousandHandwritingStrokes() async throws {
        let content = try ExportContent.content(strokes: Self.handwriting(count: 200_000))
        try await measure(content, name: "200,000 handwriting strokes")
    }

    /// Exports the content in a detached task, as the canvas does, and records the measures.
    private func measure(_ content: CanvasContent, name: String) async throws {
        let available = os_proc_available_memory()
        var lowest = available
        let clock = ContinuousClock()
        let start = clock.now
        let isDone = OSAllocatedUnfairLock(initialState: false)
        let task = Task.detached {
            defer { isDone.withLock { $0 = true } }
            return try PDFExporter.pdfData(of: content)
        }
        // The bound covers an export of 10 minutes at the poll interval (FLOW-03).
        for _ in 0..<300_000 where !isDone.withLock({ $0 }) {
            lowest = min(lowest, os_proc_available_memory())
            try await Task.sleep(for: Self.pollInterval)
        }
        let data = try await task.value
        let seconds = start.duration(to: clock.now) / .seconds(1)
        let page = try XCTUnwrap(PDFRender.firstPage(of: data))
        XCTAssertGreaterThan(page.getBoxRect(.mediaBox).width, 0, "The export made a page")
        let line = String(
            format: "export of %@: %.2f s, peak memory growth %.0f MB, PDF %.1f MB",
            name,
            seconds,
            Double(available - min(available, lowest)) / 1_048_576,
            Double(data.count) / 1_048_576
        )
        XCTContext.runActivity(named: line) { _ in }
    }
}
