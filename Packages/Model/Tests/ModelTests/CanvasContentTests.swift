import Testing

@testable import Model

@Suite("Canvas content")
struct CanvasContentTests {
    @Test("An added stroke is in the content")
    func add() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        let stroke = Fixtures.stroke(points: [
            InkPoint(x: 0, y: 0, force: 1, time: 0), InkPoint(x: 1, y: 0, force: 1, time: 0),
        ])
        try content.add(stroke)
        #expect(content.strokes[stroke.id]?.id == stroke.id)
        #expect(content.strokes.count == 1)
    }

    @Test("The canvas takes strokes up to the limit and refuses one more")
    func strokeLimit() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        var factory = Fixtures.factory()
        let points = InkPoints([
            InkPoint(x: 0, y: 0, force: 1, time: 0), InkPoint(x: 1, y: 0, force: 1, time: 0),
        ])
        func makeStroke() -> Stroke {
            Stroke(
                id: factory.identifiers.make(StrokeID.self),
                canvasID: Fixtures.canvas,
                created: factory.clock.now(),
                origin: .zero,
                width: 2,
                points: points
            )
        }
        for _ in 0..<Limits.maxStrokesPerCanvas {
            try content.add(makeStroke())
        }
        #expect(content.strokes.count == Limits.maxStrokesPerCanvas)
        #expect(throws: ModelError.strokeLimitReached) {
            try content.add(makeStroke())
        }
    }

    @Test("The limits have the values of architecture.md section 10")
    func limits() {
        #expect(Limits.maxPointsPerStroke == 16_384)
        #expect(Limits.maxStrokesPerCanvas == 200_000)
        #expect(Limits.zoomRange == 0.25...8.0)
        #expect(Limits.standardZoom == 1.0)
        #expect(Limits.maxDepth == 32)
    }
}
