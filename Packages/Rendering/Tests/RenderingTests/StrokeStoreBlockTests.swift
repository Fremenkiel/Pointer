import Geometry
import Metal
import Model
import Testing

@testable import Rendering

/// The block lists and the points of the stroke store stay bounded while a canvas erases, undoes,
/// and draws (M-04, M-05 of docs/m4-fix-plan.md).
@Suite("Stroke store blocks")
struct StrokeStoreBlockTests {
    /// The rounds of erase, undo, and new strokes.
    private static let rounds = 30

    private static func makeStore() throws -> StrokeStore {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return StrokeStore(
            arena: try PointArena(device: device, initialSlabs: 1, byteBudget: 1 << 20)
        )
    }

    /// A stroke of `count` points along a line at height `y`.
    private static func stroke(count: Int, y: Double, seed: Int) -> Stroke {
        StrokeBuilder.stroke((0..<count).map { Point(x: Double($0), y: y) }, seed: seed)
    }

    private static func liveBlocks(_ store: StrokeStore) -> Int {
        store.infos.filter { !$0.isRemoved }.reduce(0) { $0 + $1.blockCount }
    }

    /// The store and the frame clock of the rounds.
    private final class Rounds {
        let store: StrokeStore
        var frame: UInt64 = 1
        var seed = 0
        var live: [Stroke] = []

        init(store: StrokeStore) {
            self.store = store
        }

        func nextFrames() {
            for _ in 0..<4 {
                frame += 1
                store.releaseRemovals(at: frame)
            }
        }

        func stroke(count: Int, y: Double) -> Stroke {
            seed += 1
            return StrokeStoreBlockTests.stroke(count: count, y: y, seed: seed)
        }

        /// An erase that cuts 100 strokes into two longer parts each, and its undo.
        func eraseAndUndo(round: Int) {
            let cut = Array(live.prefix(100))
            let parts = cut.enumerated().flatMap { index, stroke -> [Stroke] in
                let count = 130 + (round * 7 + index) % 120
                return [
                    self.stroke(count: count, y: stroke.origin.y),
                    self.stroke(count: count + 20, y: stroke.origin.y),
                ]
            }
            for stroke in cut { store.remove(stroke.id, frame: frame + 1) }
            for part in parts { store.add(part) }
            nextFrames()
            for part in parts { store.remove(part.id, frame: frame + 1) }
            for stroke in cut { store.add(stroke) }
            nextFrames()
        }

        /// 20 new strokes, and the 20 newest strokes of before go.
        func replaceNewest(round: Int) {
            let fresh = (0..<20).map { stroke(count: 65 + (round + $0) % 200, y: 500) }
            for stroke in live.suffix(20) { store.remove(stroke.id, frame: frame + 1) }
            live = Array(live.dropLast(20)) + fresh
            for stroke in fresh { store.add(stroke) }
            nextFrames()
        }
    }

    @Test(
        "30 rounds of erase, undo, and new strokes keep the block lists under twice the live blocks"
    )
    func blockListsStayBounded() throws {
        let rounds = Rounds(store: try Self.makeStore())
        rounds.live = (0..<200).map { rounds.stroke(count: 65 + $0 % 100, y: Double($0)) }
        for stroke in rounds.live { rounds.store.add(stroke) }
        for round in 0..<Self.rounds {
            rounds.eraseAndUndo(round: round)
            rounds.replaceNewest(round: round)
        }
        let blocks = Self.liveBlocks(rounds.store)
        #expect(
            rounds.store.blockListCount < 2 * blocks,
            "The lists hold \(rounds.store.blockListCount) entries for \(blocks) live blocks"
        )
    }

    @Test("A removed stroke releases its points after the frames in flight")
    func removedPointsAreReleased() throws {
        let store = try Self.makeStore()
        weak var released: InkPoints?
        do {
            let stroke = Self.stroke(count: 5_000, y: 0, seed: 1)
            released = stroke.points
            store.add(stroke)
            store.remove(stroke.id, frame: 1)
        }
        for frame in UInt64(1)...(1 + StrokeStore.framesInFlight) {
            store.releaseRemovals(at: frame)
        }
        #expect(released == nil)
        #expect(store.count == 0)
    }
}
