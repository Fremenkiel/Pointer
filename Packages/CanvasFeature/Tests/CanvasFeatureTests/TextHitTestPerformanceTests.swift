import Foundation
import Geometry
import Model
import QuartzCore
import XCTest

@testable import CanvasFeature

/// The time of the first tap over many text boxes, on the main thread (review of M5). Before the
/// height bound of `TextEditing.box(at:in:zoom:tapTarget:)`, a tap below 10,000 stacked boxes
/// laid out each box and took 125 ms on the iPad Pro 11-inch (M4).
@MainActor
final class TextHitTestPerformanceTests: XCTestCase {
    /// The budget of the first tap: under one frame of 8.3 ms at 120 Hz, measured 0.17 ms.
    private static let budgetMilliseconds = 4.0
    private static let boxCount = 10_000
    private static let rowHeight = 90.0

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
        let editing = TextEditing()
        let start = CACurrentMediaTime()
        let hit = editing.box(at: below, in: boxes, zoom: 1, tapTarget: 44)
        let elapsed = (CACurrentMediaTime() - start) * 1_000
        let line = String(format: "first tap below 10,000 stacked boxes: %.2f ms", elapsed)
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach(["first-tap.ms": elapsed])
        XCTAssertNil(hit)
        XCTAssertLessThan(elapsed, Self.budgetMilliseconds, line)
    }
}
