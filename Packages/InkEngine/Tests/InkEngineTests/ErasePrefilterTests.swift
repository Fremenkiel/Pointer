import Geometry
import Model
import Testing

@testable import InkEngine

/// The serial filter of the bounds before the split (m10-plan.md task 3.2, review M9 section
/// 3.3, item 8).
@Suite("Erase prefilter")
struct ErasePrefilterTests {
    @Test("Candidates whose bounds miss the path change nothing in the command")
    func missesChangeNothing() throws {
        var factory = InkFixtures.factory()
        var hits: [Stroke] = []
        var mixed: [Stroke] = []
        for row in 0..<200 {
            let hit = InkFixtures.line(from: 0, to: 598, y: Double(row) * 6, factory: &factory)
            let miss = InkFixtures.line(from: 320, to: 324, y: Double(row) * 6, factory: &factory)
            hits.append(hit)
            mixed += [miss, hit]
        }
        let path = EraserPath(
            samples: (0...400).map { Point(x: 300, y: Double($0) * 3 - 3) },
            radius: 4
        )
        var first = factory
        var second = factory
        let alone = try #require(Eraser.command(erasing: hits, along: path, factory: &first))
        let among = try #require(Eraser.command(erasing: mixed, along: path, factory: &second))
        #expect(among.removed.map(\.id) == hits.map(\.id), "The order of the candidates holds")
        #expect(among.parts.map(\.points.count) == alone.parts.map(\.points.count))
        #expect(among.parts.map(\.bounds) == alone.parts.map(\.bounds))
        #expect(among.area == alone.area)
    }
}
