import Testing

@testable import Geometry

/// The bytes of a collection from its capacity, for the memory test of the stroke store (D-167).
@Suite("Storage byte counts")
struct StorageByteCountTests {
    @Test("An array counts its capacity, not its count")
    func array() {
        var values: [Int64] = []
        values.reserveCapacity(1_000)
        values.append(1)
        #expect(values.storageByteCount == values.capacity * 8)
        #expect(values.storageByteCount >= 8_000)
    }

    @Test(
        "A table takes the smallest power of two of buckets at three quarters",
        arguments: [
            (1, 2), (2, 4), (3, 4), (4, 8), (6, 8), (7, 16), (1_536, 2_048), (1_537, 4_096),
        ]
    )
    func buckets(capacity: Int, buckets: Int) {
        #expect([Int: Int].bucketCount(capacity: capacity) == buckets)
    }

    @Test("A dictionary counts each bucket and its map")
    func dictionary() {
        var table: [Int: Int] = [:]
        #expect(table.storageByteCount == 0)
        table.reserveCapacity(1_000)
        table[1] = 1
        // 1,000 entries need 2,048 buckets of 16 bytes and a map of 32 words.
        #expect(table.capacity == 1_536)
        #expect(table.storageByteCount == 2_048 * 16 + 32 * 8)
    }

    @Test("A grid counts its tables and its cell lists")
    func grid() {
        var grid = SpatialGrid<Int>(cellSize: 512, maxCellsPerItem: 4)
        let empty = grid.storageByteCount
        grid.insert(
            1,
            bounds: Rect(origin: Point(x: 10, y: 10), size: Size(width: 600, height: 10))
        )
        #expect(empty == 0)
        // Two cells of one entry of 40 bytes each, at least.
        #expect(grid.storageByteCount >= 2 * 40)
    }
}
