import Model
import Testing

@testable import Rendering

@Suite("Clipped runs of a redraw")
struct ClippedRunTests {
    /// A straight line of 101 points, 1 point apart, along x.
    private static let points = (0...100).map { InkPoint(x: Float($0), y: 0, force: 1, time: 0) }

    private func parts(of run: DetailRun, low: Float, high: Float) -> [DetailRun] {
        var result: [DetailRun] = []
        let box = ClipBox(low: SIMD2(low, -1), high: SIMD2(high, 1))
        run.forEachClipped(points: Self.points, box: box) { result.append($0) }
        return result
    }

    @Test("A box in the middle gives one part with the neighbor points of the run")
    func middle() throws {
        let run = DetailRun(start: 0, end: 100, stride: 1, pieces: 1)
        let found = parts(of: run, low: 49.5, high: 50.5)
        let part = try #require(found.first)
        #expect(found.count == 1)
        #expect(part.start <= 49 && part.end >= 51)
        #expect(part.start > 40 && part.end < 60)
        #expect(part.previousOffset == 1)
        #expect(part.nextOffset == 1)
    }

    @Test("A box at an end keeps the end of the run, and a box outside gives nothing")
    func ends() {
        let run = DetailRun(start: 0, end: 100, stride: 4, pieces: 2)
        let first = parts(of: run, low: -5, high: 2)
        #expect(first.first?.start == 0)
        #expect(first.first?.previousOffset == 0)
        let last = parts(of: run, low: 99, high: 120)
        #expect(last.last?.end == 100)
        #expect(last.last?.nextOffset == 0)
        #expect(parts(of: run, low: 200, high: 300).isEmpty)
    }

    @Test("A box over the whole run gives the run itself")
    func whole() {
        let run = DetailRun(start: 0, end: 100, stride: 3, pieces: 1)
        #expect(parts(of: run, low: -10, high: 110) == [run])
    }
}
