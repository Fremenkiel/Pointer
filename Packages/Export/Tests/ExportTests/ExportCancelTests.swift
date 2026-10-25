import Export
import Foundation
import Model
import QuartzCore
import XCTest

/// The cancel of an export at the close of its canvas (review after M9, section 3.2, item 9).
/// The export of 200,000 strokes holds about 1 GB of points for up to 17 s.
@MainActor
final class ExportCancelTests: XCTestCase {
    /// How long the export runs before the cancel.
    private static let runBeforeCancel = Duration.milliseconds(200)
    /// The longest time from the cancel to the end of the export.
    private static let maxSecondsAfterCancel = 1.0

    func testCancelStopsAnExportOfTwoHundredThousandStrokes() async throws {
        let content = try ExportContent.content(
            strokes: ExportPerformanceTests.handwriting(count: 200_000)
        )
        let export = Task.detached {
            Result { () throws(ExportError) -> Data in try PDFExporter.pdfData(of: content) }
        }
        try await Task.sleep(for: Self.runBeforeCancel)
        let start = CACurrentMediaTime()
        export.cancel()
        let result = await export.value
        let seconds = CACurrentMediaTime() - start
        XCTAssertLessThan(seconds, Self.maxSecondsAfterCancel, "It ended after \(seconds) s")
        guard case .failure(let error) = result else {
            return XCTFail("The export finished its PDF after the cancel")
        }
        XCTAssertEqual(error, .cancelled)
    }
}
