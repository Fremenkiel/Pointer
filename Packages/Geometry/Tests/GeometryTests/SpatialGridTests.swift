import Testing

@testable import Geometry

@Suite("Spatial grid")
struct SpatialGridTests {
    private func items(in grid: SpatialGrid<Int>, touching rect: Rect) -> [Int] {
        var found: [Int] = []
        grid.forEachItem(touching: rect) { found.append($0) }
        return found.sorted()
    }

    @Test("A query finds the items that touch the rectangle, each one once")
    func query() {
        var grid = SpatialGrid<Int>(cellSize: 512, maxCellsPerItem: 4_096)
        grid.insert(1, bounds: Rect(minX: 0, minY: 0, maxX: 10, maxY: 10))
        grid.insert(2, bounds: Rect(minX: -600, minY: 100, maxX: 1500, maxY: 120))
        grid.insert(3, bounds: Rect(minX: 5000, minY: 5000, maxX: 5010, maxY: 5010))
        #expect(
            items(in: grid, touching: Rect(minX: -1000, minY: -1000, maxX: 1000, maxY: 1000)) == [
                1, 2,
            ]
        )
        #expect(items(in: grid, touching: Rect(minX: 1400, minY: 0, maxX: 1600, maxY: 200)) == [2])
        #expect(items(in: grid, touching: Rect(minX: 20, minY: 20, maxX: 30, maxY: 30)).isEmpty)
    }

    @Test("A query larger than the occupied cells gives the same result")
    func largeQuery() {
        var grid = SpatialGrid<Int>(cellSize: 512, maxCellsPerItem: 4_096)
        grid.insert(1, bounds: Rect(minX: 0, minY: 0, maxX: 2000, maxY: 10))
        grid.insert(
            2,
            bounds: Rect(minX: 1_000_000, minY: 1_000_000, maxX: 1_000_001, maxY: 1_000_001)
        )
        let all = Rect(minX: -2_000_000, minY: -2_000_000, maxX: 2_000_000, maxY: 2_000_000)
        #expect(items(in: grid, touching: all) == [1, 2])
    }

    @Test("A removed item is not found, and its cells are freed")
    func remove() {
        var grid = SpatialGrid<Int>(cellSize: 512, maxCellsPerItem: 4_096)
        grid.insert(1, bounds: Rect(minX: 0, minY: 0, maxX: 1100, maxY: 10))
        grid.insert(2, bounds: Rect(minX: 0, minY: 0, maxX: 10, maxY: 10))
        #expect(grid.count == 2)
        #expect(grid.occupiedCellCount == 3)
        let first = grid.remove(1)
        let second = grid.remove(1)
        #expect(first)
        #expect(!second)
        #expect(grid.count == 1)
        #expect(grid.occupiedCellCount == 1)
        #expect(grid.bounds(of: 1) == nil)
        #expect(items(in: grid, touching: Rect(minX: 0, minY: 0, maxX: 2000, maxY: 2000)) == [2])
    }

    @Test("Negative coordinates land in negative cells")
    func negativeCells() {
        let grid = SpatialGrid<Int>(cellSize: 512, maxCellsPerItem: 4_096)
        #expect(grid.cell(containing: Point(x: -1, y: 511.9)) == GridCell(column: -1, row: 0))
        #expect(
            grid.cell(containing: Point(x: 1e300, y: -1e300)).column
                == SpatialGrid<Int>.maxCellCoordinate
        )
    }
}

@Suite("Spatial grid reserve")
struct SpatialGridReserveTests {
    @Test("A reserve keeps the grid empty and lets the items in", arguments: [0, 1, 5_000])
    func reserve(count: Int) {
        var grid = SpatialGrid<Int>(cellSize: 512, maxCellsPerItem: 4_096)
        grid.reserveCapacity(count)
        #expect(grid.count == 0)
        for id in 0..<count {
            grid.insert(id, bounds: Rect(origin: Point(x: Double(id), y: 0), size: .zero))
        }
        #expect(grid.count == count)
    }
}
