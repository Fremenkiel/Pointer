import Geometry
import Metal
import Model
import Testing

@testable import Rendering

@MainActor
@Suite("Point arena and eviction")
struct PointArenaTests {
    private func makeArena(slabs: Int, budgetSlabs: Int) throws -> PointArena {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return try PointArena(
            device: device,
            initialSlabs: slabs,
            byteBudget: budgetSlabs * PointArena.bytesPerSlab
        )
    }

    @Test("The arena adds one buffer at a time up to its budget, and no block crosses a buffer")
    func growth() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let arena = try PointArena(
            device: device,
            initialSlabs: 1,
            byteBudget: 5 * PointArena.bytesPerSlab,
            slabsPerBuffer: 2
        )
        let points = InkPoints((0..<16_384).map { InkPoint(x: Float($0), y: 0, force: 1, time: 0) })
        #expect(arena.buffers.count == 1)
        let first = try #require(arena.allocate(points: points.count))
        arena.write(points, to: first)
        let second = try #require(arena.allocate(points: points.count))
        #expect(arena.buffers.count == 1)
        #expect(arena.location(of: second) == (buffer: 0, offset: SlabAllocator.slabPoints))
        let third = try #require(arena.allocate(points: points.count))
        #expect(arena.buffers.count == 2)
        #expect(arena.location(of: third) == (buffer: 1, offset: 0))
        _ = try #require(arena.allocate(points: points.count))
        let fifth = try #require(arena.allocate(points: points.count))
        #expect(arena.buffers.count == 3)
        #expect(arena.buffers[2].length == PointArena.bytesPerSlab)
        #expect(arena.location(of: fifth) == (buffer: 2, offset: 0))
        #expect(arena.allocate(points: points.count) == nil)
        #expect(arena.footprint == 5 * PointArena.bytesPerSlab)
        #expect(arena.usedBytes == 5 * PointArena.bytesPerSlab)
    }

    @Test("A full arena evicts the strokes drawn least recently and loads them again")
    func eviction() throws {
        let store = StrokeStore(arena: try makeArena(slabs: 1, budgetSlabs: 2))
        let long = (0..<10_000).map { Point(x: Double($0) * 0.1, y: 0) }
        let slots = (0..<3).map { store.add(StrokeBuilder.stroke(long, seed: $0)) }
        #expect(store.residentInfo(of: slots[0], frame: 1)?.block != nil)
        #expect(store.residentInfo(of: slots[1], frame: 2)?.block != nil)
        let third = store.residentInfo(of: slots[2], frame: 10)
        #expect(third?.block != nil)
        #expect(store.infos[slots[0]].block == nil)
        #expect(store.infos[slots[1]].block != nil)
        let again = store.residentInfo(of: slots[0], frame: 20)
        #expect(again?.block != nil)
        #expect(store.infos[slots[1]].block == nil)
    }

    @Test("Strokes drawn in the last frames stay in the arena")
    func protection() throws {
        let store = StrokeStore(arena: try makeArena(slabs: 1, budgetSlabs: 1))
        let long = (0..<10_000).map { Point(x: Double($0) * 0.1, y: 0) }
        let first = store.add(StrokeBuilder.stroke(long, seed: 1))
        let second = store.add(StrokeBuilder.stroke(long, seed: 2))
        #expect(store.residentInfo(of: first, frame: 5)?.block != nil)
        #expect(store.residentInfo(of: second, frame: 6) == nil)
        #expect(store.infos[first].block != nil)
    }
}
