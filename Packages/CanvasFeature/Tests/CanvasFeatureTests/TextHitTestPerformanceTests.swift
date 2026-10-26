import Foundation
import Geometry
import Model
import QuartzCore
import XCTest

@testable import CanvasFeature

/// The time of the first tap over many text boxes, on the main thread (review of M5). Before the
/// height bound of `TextEditing.box(at:in:zoom:tapTarget:)`, a tap below 10,000 stacked boxes
/// laid out each box and took 125 ms on the iPad Pro 11-inch (M4).
///
/// Each tap goes to a new `TextEditing`, so each is a first tap without known sizes. The test
/// before this one can leave the CPU in a slower state: after `TextBuildPerformanceTests`, one
/// tap took 0.25 to 0.29 ms instead of 0.18 ms, and about 50 taps brought it back (m10-plan.md
/// section 6.44). Thus warm-up taps run first, and the sample is the median of the measured taps
/// (D-177).
@MainActor
final class TextHitTestPerformanceTests: XCTestCase {
    /// The budget of the first tap: under one frame of 8.3 ms at 120 Hz, measured 0.17 ms.
    private static let budgetMilliseconds = 4.0
    private static let boxCount = 10_000
    private static let rowHeight = 90.0
    /// The taps before the measure, about 25 ms on the iPad.
    private static let warmUpTaps = 100
    /// The measured taps. The sample is their median.
    private static let measuredTaps = 11

    func testFirstTapBelowTenThousandStackedBoxes() throws {
        let device = DeviceID(rawValue: UUID())
        let canvas = CanvasID(rawValue: UUID())
        let meta = RecordMeta(created: HybridTimestamp(wallMillis: 1, counter: 0, device: device))
        let text = String(repeating: "node ", count: 40)
        let key = try FractionalIndex(rawValue: "V")
        var boxes: [TextBoxID: TextBox] = [:]
        for index in 0..<Self.boxCount {
            let box = try TextBox(
                id: TextBoxID(rawValue: UUID()),
                meta: meta,
                canvasID: canvas,
                origin: Point(x: 0, y: Double(index) * Self.rowHeight),
                text: text,
                sortKey: key
            )
            boxes[box.id] = box
        }
        let below = Point(x: 50, y: Double(Self.boxCount) * Self.rowHeight + 10_000)
        for _ in 0..<Self.warmUpTaps {
            XCTAssertNil(TextEditing().box(at: below, in: boxes, zoom: 1, tapTarget: 44))
        }
        var taps: [Double] = []
        for _ in 0..<Self.measuredTaps {
            let editing = TextEditing()
            let start = CACurrentMediaTime()
            let hit = editing.box(at: below, in: boxes, zoom: 1, tapTarget: 44)
            taps.append((CACurrentMediaTime() - start) * 1_000)
            XCTAssertNil(hit)
        }
        let elapsed = taps.sorted()[Self.measuredTaps / 2]
        let line = String(format: "first tap below 10,000 stacked boxes: %.2f ms", elapsed)
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach(["first-tap.median.ms": elapsed])
        XCTAssertLessThan(elapsed, Self.budgetMilliseconds, line)
    }
}
