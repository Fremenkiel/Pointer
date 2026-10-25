import Testing

@testable import Geometry

/// The position table of a crowded cell (m10-plan.md task 3.2, review M9 section 3.3, item 9).
@Suite("Crowded grid cell")
struct CrowdedCellTests {
    /// A grid with `count` items in one cell, each of 4 by 4 points.
    private static func grid(count: Int) -> SpatialGrid<Int> {
        var grid = SpatialGrid<Int>(cellSize: 512, maxCellsPerItem: 4_096)
        for index in 0..<count {
            grid.insert(index, bounds: Self.bounds(of: index))
        }
        return grid
    }

    private static func bounds(of index: Int) -> Rect {
        let x = Double(index % 100) * 5
        let y = Double(index / 100) * 0.25
        return Rect(minX: x, minY: y, maxX: x + 4, maxY: y + 4)
    }

    private static func items(in grid: SpatialGrid<Int>) -> Set<Int> {
        var found = Set<Int>()
        grid.forEachItem(touching: Rect(minX: 0, minY: 0, maxX: 511, maxY: 511)) {
            found.insert($0)
        }
        return found
    }

    @Test(
        "A cell at the threshold has no table, and one more entry builds it",
        arguments: [SpatialGrid<Int>.indexedCellCount, SpatialGrid<Int>.indexedCellCount + 1]
    )
    func threshold(count: Int) throws {
        let grid = Self.grid(count: count)
        let cell = try #require(grid.cells.values.first)
        #expect(grid.cells.count == 1)
        #expect((cell.positions != nil) == (count > SpatialGrid<Int>.indexedCellCount))
        #expect(Self.items(in: grid) == Set(0..<count))
    }

    @Test("Removals in any order keep each position right, and inserts after them too")
    func removals() throws {
        let count = SpatialGrid<Int>.indexedCellCount * 3
        var grid = Self.grid(count: count)
        var live = Set(0..<count)
        var generator = SplitMix(seed: 7)
        for _ in 0..<count / 2 {
            let id = try #require(live.randomElement(using: &generator))
            let removed = grid.remove(id)
            #expect(removed, "Item \(id) was in the grid")
            live.remove(id)
        }
        for index in count..<count + 100 {
            grid.insert(index, bounds: Self.bounds(of: index))
            live.insert(index)
        }
        let cell = try #require(grid.cells.values.first)
        let positions = try #require(cell.positions)
        #expect(positions.count == cell.entries.count)
        for (position, entry) in cell.entries.enumerated() {
            #expect(positions[entry.id] == position, "Position of \(entry.id)")
        }
        #expect(Self.items(in: grid) == live)
        for id in live {
            let removed = grid.remove(id)
            #expect(removed, "Item \(id) was in the grid")
        }
        #expect(grid.cells.isEmpty, "The empty cell goes")
    }
}

/// A seeded generator, so that a failure repeats.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
