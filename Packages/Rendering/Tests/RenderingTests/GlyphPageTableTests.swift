import Metal
import Synchronization
import Testing

@testable import Rendering

/// The placement indices of the page table (review of 2026-10-28, 3.2.12).
@Suite("Glyph page table")
struct GlyphPageTableTests {
    @Test("A failed buffer of the places leaves the free indices as they were")
    func failedBufferKeepsIndex() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let fails = Mutex(true)
        let table = try #require(
            GlyphPageTable(device: device, byteBudget: 16 << 20) { length in
                guard !fails.withLock({ $0 }) else { return nil }
                return device.makeBuffer(length: length, options: .storageModeShared)
            }
        )
        let placement = GlyphAtlas.Placement(
            page: 0,
            origin: SIMD2(0, 0),
            size: SIMD2(4, 4),
            bearing: SIMD2(0, 0)
        )
        #expect(table.register(placement) == -1)
        fails.withLock { $0 = false }
        #expect(table.register(placement) == 0, "The index of the failed register is free again")
        #expect(table.register(placement) == 1)
    }
}
