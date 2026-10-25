import Testing

@testable import Model

/// The chunks of the erase split and of the layouts of a load at their limits (TEST-06).
@Suite("Parallel chunks")
struct ParallelChunksTests {
    private static let size = ParallelChunks.minimumSize
    private static let most = ParallelChunks.maxCount
    /// Item counts at each bound and past it, with their chunk counts.
    private static let cases: [(items: Int, chunks: Int)] = [
        (0, 1), (1, 1), (size - 1, 1), (size, 1), (2 * size - 1, 1), (2 * size, 2),
        (most * size - 1, most - 1), (most * size, most), (most * size + 1, most),
        (Limits.maxNodesPerCanvas, most),
    ]

    @Test("A chunk holds at least the minimum size, up to the most chunks")
    func count() {
        for (items, chunks) in Self.cases {
            #expect(ParallelChunks.count(of: items) == chunks, "\(items) items")
        }
    }

    @Test(
        "The chunks cover each item once and in order",
        arguments: [0, 1, size, most * size + 1, Limits.maxNodesPerCanvas]
    )
    func ranges(items: Int) {
        let chunks = ParallelChunks.count(of: items)
        var next = 0
        for index in 0..<chunks {
            let range = ParallelChunks.range(of: index, chunkCount: chunks, itemCount: items)
            #expect(range.lowerBound == next, "Chunk \(index) starts where the last one ended")
            next = range.upperBound
        }
        #expect(next == items)
    }
}
