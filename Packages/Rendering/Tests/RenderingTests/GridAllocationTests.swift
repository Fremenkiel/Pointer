import Geometry
import XCTest

/// The removal from the spatial grid allocates nothing (P-02 of the M4 fix plan, phase 3,
/// task 2). The grid is a Tier A type, but the allocation counter needs the `malloc_logger` hook
/// of `AllocationCounter+Unsafe.swift`, so the test runs here (D-80). The removals run on the
/// main thread, so the count takes the main thread only: other tests run at the same time.
final class GridAllocationTests: XCTestCase {
    func testThousandRemovalsMakeNoAllocation() throws {
        var grid = SpatialGrid<Int>(cellSize: 512, maxCellsPerItem: 4_096)
        for index in 0..<20_000 {
            let x = Double(index % 200) * 40 - 4_000
            let y = Double(index / 200) * 40 - 2_000
            grid.insert(index, bounds: Rect(minX: x - 1, minY: y - 1, maxX: x + 31, maxY: y + 8))
        }
        for row in 0..<1_000 {
            let y = Double(row) * 1.5 - 750
            grid.insert(20_000 + row, bounds: Rect(minX: -301, minY: y - 1, maxX: 299, maxY: y + 1))
        }
        let count = try XCTUnwrap(
            AllocationCounter.countMainThread {
                for index in 20_000..<21_000 { grid.remove(index) }
            }
        )
        XCTAssertEqual(grid.count, 20_000)
        XCTAssertEqual(count, 0, "1,000 removals made \(count) allocations")
    }
}
