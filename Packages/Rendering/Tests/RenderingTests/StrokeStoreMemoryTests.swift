import Darwin
import Metal
import Model
import XCTest

@testable import Rendering

/// The memory of the stroke store of a full canvas (the M2 fix plan, phase 4, task 5).
@MainActor
final class StrokeStoreMemoryTests: XCTestCase {
    /// The bytes of the collections of the store of 200,000 handwriting strokes at most. The
    /// store took 68.7 MB of heap on 2026-10-18, most of it in the spatial grid and the ID map.
    /// The product owner accepted it, and this limit guards against a regression (D-49).
    ///
    /// The test sums the capacities of the collections, because the heap growth depends on the
    /// blocks that earlier tests freed: it took 63.1 to 84.3 MB in full runs (D-167).
    private static let maxStoreBytes = 75 << 20
    /// The stored fields of one stroke at most, in bytes.
    private static let maxDrawInfoBytes = 48

    func testDrawInfoTakesFortyEightBytes() {
        XCTAssertLessThanOrEqual(
            MemoryLayout<StrokeStore.DrawInfo>.stride,
            Self.maxDrawInfoBytes
        )
    }

    func testStoreOfTwoHundredThousandHandwritingStrokes() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let before = Self.heap()
        let content = PerformanceContent.handwriting(count: 200_000)
        let afterContent = Self.heap()
        let arena = try PointArena(device: device, initialSlabs: 1, byteBudget: 1 << 20)
        let store = StrokeStore(arena: arena)
        // The load path of the renderer, `FrameRenderer.load`.
        store.add(contentsOf: content)
        let afterStore = Self.heap()
        let heapBytes = afterStore.bytes - afterContent.bytes
        let storeBytes = store.storageByteCount
        let contentBlocks = afterContent.blocks - before.blocks
        let line = String(
            format: "store %.1f MB, heap growth %.1f MB, content %d heap blocks for %d strokes",
            Double(storeBytes) / Double(1 << 20),
            Double(heapBytes) / Double(1 << 20),
            contentBlocks,
            content.count
        )
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach([
            "store.mb": Double(storeBytes) / Double(1 << 20),
            "heap.mb": Double(heapBytes) / Double(1 << 20),
        ])
        XCTAssertLessThanOrEqual(storeBytes, Self.maxStoreBytes, line)
        XCTAssertEqual(store.count, content.count)
    }

    /// The bytes and the blocks in use in the default malloc zone.
    private static func heap() -> (bytes: Int, blocks: Int) {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return (Int(statistics.size_in_use), Int(statistics.blocks_in_use))
    }
}
