import Geometry
import Model
import Testing

@testable import InkEngine

/// The serial filter of the bounds before the split (the M10 plan task 3.2, review M9 section
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

/// The bounds of a stroke hold half its width, and the bounds of a path hold the radius, so
/// the prefilter needs no second radius (review of 2026-10-28, 3.2.8).
@Suite("Erase prefilter bounds")
struct ErasePrefilterBoundsTests {
    @Test("A stroke between one and two radii from the path leaves the prefilter and the hit test")
    func strokeOutsideReach() throws {
        var factory = InkFixtures.factory()
        // The path covers x up to 304 with its radius, and the ink of the line starts at 306.
        let touching = InkFixtures.line(from: 300, to: 400, factory: &factory)
        let apart = InkFixtures.line(from: 307, to: 401, factory: &factory)
        let path = EraserPath(samples: [Point(x: 300, y: -10), Point(x: 300, y: 10)], radius: 4)
        let near = Eraser.nearCandidates([touching, apart], along: path)
        #expect(near.map(\.id) == [touching.id])
        #expect(StrokeHitTest.coveredRanges(of: apart, by: path).isEmpty)
        #expect(!StrokeHitTest.coveredRanges(of: touching, by: path).isEmpty)
        let command = try #require(
            Eraser.command(erasing: [apart, touching], along: path, factory: &factory)
        )
        #expect(command.removed.map(\.id) == [touching.id])
    }
}
