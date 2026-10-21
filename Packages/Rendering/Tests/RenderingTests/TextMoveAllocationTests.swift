import Geometry
import Model
import XCTest

@testable import Rendering

/// The heap allocations of one drag step of a text box on the render thread (review of M5).
/// Before the store kept the layout of an unchanged text, a step of a box of 200 characters laid
/// out its text again with 58 allocations, and a box of 10,000 characters took 0.36 ms.
@MainActor
final class TextMoveAllocationTests: XCTestCase {
    /// The allocations of a step with a kept layout: the grid cell lists and the dictionary
    /// entry. The step measured 4 on the iPad Pro 11-inch (M4).
    private static let allowedAllocations = 8

    func testMoveStepKeepsTheLayout() throws {
        let store = TextStore()
        let creator = DeviceID(rawValue: UUID())
        var box = try TextBox(
            id: TextBoxID(rawValue: UUID()),
            meta: RecordMeta(created: HybridTimestamp(wallMillis: 1, counter: 0, device: creator)),
            canvasID: CanvasID(rawValue: UUID()),
            origin: .zero,
            text: String(repeating: "node ", count: 40),
            sortKey: FractionalIndex(rawValue: "V")
        )
        store.add(box)
        var counts: [Int] = []
        for step in 1...20 {
            box = try box.moving(to: Point(x: Double(step), y: 0), at: box.meta.modified)
            let moved = box
            if let count = AllocationCounter.countMainThread({ store.add(moved) }) {
                counts.append(count)
            }
        }
        let median = counts.sorted()[counts.count / 2]
        let line = "allocations of a move step: median \(median)"
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThanOrEqual(median, Self.allowedAllocations, line)
        XCTAssertEqual(store.entries[box.id]?.origin, box.origin)
    }

    func testEditedTextGetsANewLayout() throws {
        let store = TextStore()
        let creator = DeviceID(rawValue: UUID())
        let box = try TextBox(
            id: TextBoxID(rawValue: UUID()),
            meta: RecordMeta(created: HybridTimestamp(wallMillis: 1, counter: 0, device: creator)),
            canvasID: CanvasID(rawValue: UUID()),
            origin: .zero,
            text: "node",
            sortKey: FractionalIndex(rawValue: "V")
        )
        store.add(box)
        let edited = try box.editing(text: "node\nnode", at: box.meta.modified)
        store.add(edited)
        XCTAssertEqual(store.entries[box.id]?.layout.lineCount, 2)
    }
}
