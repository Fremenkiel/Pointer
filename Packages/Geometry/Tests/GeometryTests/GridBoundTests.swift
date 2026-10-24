import Testing

@testable import Geometry

/// The cell count of an item and the bound of the cells per item (task 1.5 of
/// docs/m9-plan.md, D-158).
@Suite("Grid cells per item")
struct GridBoundTests {
    @Test(
        "The cell count follows the cells that the bounds touch",
        arguments: [
            (Rect(origin: Point(x: 10, y: 10), size: Size(width: 0, height: 0)), 1),
            (Rect(origin: Point(x: 10, y: 10), size: Size(width: 501, height: 0)), 1),
            (Rect(origin: Point(x: 10, y: 10), size: Size(width: 502, height: 0)), 2),
            (Rect(origin: Point(x: -1, y: -1), size: Size(width: 2, height: 2)), 4),
            (Rect(origin: Point(x: 0, y: 0), size: Size(width: 2_048, height: 1_024)), 15),
        ]
    )
    func count(bounds: Rect, cells: Int) {
        #expect(GridCell.count(covering: bounds, cellSize: 512) == cells)
    }

    @Test("A far item lands in the edge cells, so its count stays small")
    func farItem() {
        let far = Rect(origin: Point(x: 1e300, y: -1e300), size: Size(width: 1e299, height: 1))
        #expect(GridCell.count(covering: far, cellSize: 512) == 1)
    }

    @Test("An item at the bound goes in and out of the grid")
    func atBound() {
        var grid = SpatialGrid<Int>(cellSize: 512, maxCellsPerItem: 4)
        let bounds = Rect(origin: Point(x: 10, y: 10), size: Size(width: 600, height: 600))
        grid.insert(1, bounds: bounds)
        #expect(grid.occupiedCellCount == 4)
        let removed = grid.remove(1)
        #expect(removed)
        #expect(grid.occupiedCellCount == 0)
    }

    @Test("An item one cell past the bound stops the program")
    func pastBound() async {
        await #expect(processExitsWith: .failure) {
            var grid = SpatialGrid<Int>(cellSize: 512, maxCellsPerItem: 4)
            grid.insert(
                1,
                bounds: Rect(origin: Point(x: 10, y: 10), size: Size(width: 1_100, height: 600))
            )
        }
    }
}
