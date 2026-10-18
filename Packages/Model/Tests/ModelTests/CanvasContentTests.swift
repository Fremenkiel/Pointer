import Geometry
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

    @Test("The canvas takes cards and text boxes up to the node limit and refuses one more")
    func nodeLimit() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        var identifiers = IdentifierFactory(
            wallClock: FixedWallClock(millis: 1),
            random: SeededRandom(state: 5)
        )
        let half = Limits.maxNodesPerCanvas / 2
        for _ in 0..<half {
            try content.add(RecordTests.card(id: identifiers.make()))
            try content.add(RecordTests.textBox(id: identifiers.make(), text: "x"))
        }
        #expect(content.nodeCount == Limits.maxNodesPerCanvas)
        #expect(content.cards.count == half)
        #expect(content.textBoxes.count == half)
        #expect(throws: ModelError.nodeLimitReached) {
            try content.add(RecordTests.card(id: identifiers.make()))
        }
        #expect(throws: ModelError.nodeLimitReached) {
            try content.add(RecordTests.textBox(id: identifiers.make(), text: "x"))
        }
    }

    @Test("New content has no nodes and no erase records")
    func emptyContent() {
        let content = CanvasContent(canvasID: Fixtures.canvas)
        #expect(content.nodeCount == 0)
        #expect(content.erased.isEmpty)
    }

    @Test("The canvas of a workspace and of a card has the ID of its owner")
    func canvasIDs() {
        let workspace: WorkspaceID = Fixtures.id(7)
        let card: CardID = Fixtures.id(8)
        #expect(CanvasID(workspace).rawValue == workspace.rawValue)
        #expect(CanvasID(card).rawValue == card.rawValue)
    }

    @Test("The limits have the values of architecture.md section 10")
    func limits() {
        #expect(Limits.maxPointsPerStroke == 16_384)
        #expect(Limits.maxStrokesPerCanvas == 200_000)
        #expect(Limits.zoomRange == 0.25...8.0)
        #expect(Limits.standardZoom == 1.0)
        #expect(Limits.maxDepth == 32)
        #expect(Limits.maxNodesPerCanvas == 10_000)
        #expect(Limits.maxTextLength == 10_000)
        #expect(Limits.maxWorkspaces == 1_000)
        #expect(Limits.maxTitleLength == 120)
        #expect(Limits.maxSortKeyLength == 64)
        #expect(Limits.minCardWidth == 64)
        #expect(Limits.minCardHeight == 48)
    }
}
