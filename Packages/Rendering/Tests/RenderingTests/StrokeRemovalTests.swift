import Geometry
import Metal
import Model
import Testing

@testable import Rendering

@MainActor
@Suite("Stroke removal and slot reuse")
struct StrokeRemovalTests {
    private func makeStore() throws -> StrokeStore {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return StrokeStore(
            arena: try PointArena(device: device, initialSlabs: 1, byteBudget: 1 << 20)
        )
    }

    private func stroke(_ seed: Int) -> Stroke {
        StrokeBuilder.curve(at: Point(x: 0, y: Double(seed) * 10), seed: seed)
    }

    @Test("A removed stroke leaves the grid at once and keeps its block for the frames in flight")
    func removal() throws {
        let store = try makeStore()
        let first = stroke(1)
        let slot = store.add(first)
        #expect(store.makeResident(slot, frame: 1)?.block != nil)
        #expect(store.remove(first.id, frame: 1))
        #expect(store.count == 0)
        #expect(store.grid.count == 0)
        #expect(store.infos[slot].isRemoved)
        store.releaseRemovals(at: 1 + StrokeStore.framesInFlight - 1)
        #expect(store.infos[slot].block != nil)
        store.releaseRemovals(at: 1 + StrokeStore.framesInFlight)
        #expect(store.infos[slot].block == nil)
        #expect(store.arena.usedBytes == 0)
    }

    @Test("A new stroke takes a released slot and its spacing range")
    func reuse() throws {
        let store = try makeStore()
        let first = stroke(1)
        let slot = store.add(first)
        let firstBlock = store.infos[slot].firstBlock
        store.remove(first.id, frame: 1)
        store.releaseRemovals(at: 1 + StrokeStore.framesInFlight)
        let second = stroke(2)
        #expect(store.add(second) == slot)
        #expect(!store.infos[slot].isRemoved)
        #expect(store.infos[slot].firstBlock == firstBlock)
        #expect(store.count == 1)
        #expect(store.makeResident(slot, frame: 10)?.block != nil)
    }

    @Test("A slot is not reused before its removal is released")
    func noEarlyReuse() throws {
        let store = try makeStore()
        let first = stroke(1)
        let slot = store.add(first)
        store.remove(first.id, frame: 5)
        #expect(store.add(stroke(2)) != slot)
        #expect(!store.remove(first.id, frame: 5))
    }
}
