import Export
import Foundation
import Geometry
import Model
import XCTest
import os

/// The time, the peak memory growth, and the size of an export of large canvases (M8 task 2.7,
/// PERF-03). The budgets of D-144 are the highest measures of task 2.7 plus about 15 %. The
/// content with 10,000 text boxes has no budget, and the test records it only.
///
/// Each test exports once. The memory of the export goes back to the allocator of the process,
/// not to the system, so a second export in the same test shows too little growth.
@MainActor
final class ExportPerformanceTests: XCTestCase {
    /// The budget of one export (D-144).
    struct Budget {
        let seconds: Double
        let megabytes: Double
    }

    /// The budget of the export of D-56 (D-144).
    private static let d56Budget = Budget(seconds: 8.5, megabytes: 180)
    /// The budget of the export of 200,000 handwriting strokes (D-144).
    private static let handwritingBudget = Budget(seconds: 17, megabytes: 370)

    /// The time between two reads of the available memory during an export.
    /// A copy of a PDF of 80 MB takes a few milliseconds, so a longer interval misses its peak
    /// (m8-plan.md section 6.4).
    private static let pollInterval = Duration.microseconds(250)

    /// The content of D-56: 20,000 strokes of 300 points, 5,000 cards, and 5,000 text boxes of
    /// 200 characters, as `D56Library` stores it.
    func testExportOfD56Canvas() async throws {
        let content = try ExportContent.content(
            strokes: Self.d56Strokes(),
            textBoxes: Self.textBoxes(count: 5_000),
            cards: Self.cards(count: 5_000)
        )
        try await measure(
            content,
            name: "D-56: 20,000 strokes, 5,000 cards, 5,000 text boxes",
            budget: Self.d56Budget
        )
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
        try await measure(
            content,
            name: "200,000 handwriting strokes",
            budget: Self.handwritingBudget
        )
    }

    /// Exports the content in a detached task, as the canvas does, records the measures, and
    /// fails above the budget.
    private func measure(
        _ content: CanvasContent,
        name: String,
        budget: Budget? = nil
    ) async throws {
        // Other tests of a full run free and take memory, so the measure starts at steady memory,
        // as the open of the canvas does (D-93). `OnScreenCanvas` is in the same test bundle.
        try await OnScreenCanvas.waitForSteadyMemory()
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
        for _ in 0..<2_400_000 where !isDone.withLock({ $0 }) {
            lowest = min(lowest, os_proc_available_memory())
            try await Task.sleep(for: Self.pollInterval)
        }
        let data = try await task.value
        let seconds = start.duration(to: clock.now) / .seconds(1)
        let page = try XCTUnwrap(PDFRender.firstPage(of: data))
        XCTAssertGreaterThan(page.getBoxRect(.mediaBox).width, 0, "The export made a page")
        let megabytes = Double(available - min(available, lowest)) / 1_048_576
        let line = String(
            format: "export of %@: %.2f s, peak memory growth %.0f MB, PDF %.1f MB",
            name,
            seconds,
            megabytes,
            Double(data.count) / 1_048_576
        )
        XCTContext.runActivity(named: line) { _ in }
        guard let budget else { return }
        XCTAssertLessThanOrEqual(seconds, budget.seconds, line)
        XCTAssertLessThanOrEqual(megabytes, budget.megabytes, line)
    }
}
