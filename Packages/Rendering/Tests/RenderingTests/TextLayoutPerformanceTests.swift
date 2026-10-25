import Model
import XCTest

@testable import Rendering

/// The time of the layout of the text boxes of D-56: 5,000 boxes of 200 characters (task 2.1 of
/// docs/m5-plan.md). The test records the time and sets no budget.
@MainActor
final class TextLayoutPerformanceTests: XCTestCase {
    func testLayoutOfFiveThousandTextBoxes() {
        let text = String(repeating: "node ", count: 40)
        var times: [Double] = []
        for _ in 0..<5 {
            let start = ContinuousClock.now
            var lines = 0
            for _ in 0..<5_000 {
                lines += TextLayout(text: text).lineCount
            }
            let elapsed = ContinuousClock.now - start
            let parts = elapsed.components
            times.append(Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15)
            XCTAssertGreaterThanOrEqual(lines, 5_000)
        }
        let sorted = times.sorted()
        let line = String(format: "text layout of 5,000 boxes: median %.1f ms", sorted[2])
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach(["layout.median.ms": sorted[2]])
    }
}
