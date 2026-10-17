import Geometry
import Model
import Testing

@Suite("Stroke builder of the tests")
struct StrokeBuilderTests {
    @Test("Each seed up to the stroke limit gives its own stroke ID")
    func uniqueIDs() {
        let points = [Point(x: 0, y: 0), Point(x: 10, y: 0)]
        let ids = Set(
            (0..<Limits.maxStrokesPerCanvas).map { StrokeBuilder.stroke(points, seed: $0).id }
        )
        #expect(ids.count == Limits.maxStrokesPerCanvas)
    }

    @Test("The performance content has one stroke ID per stroke")
    func uniqueContentIDs() {
        let strokes = PerformanceContent.dense(count: 1_000, points: 2)
        #expect(Set(strokes.map(\.id)).count == strokes.count)
    }
}
