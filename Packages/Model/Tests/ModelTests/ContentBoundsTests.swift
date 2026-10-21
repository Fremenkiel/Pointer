import Geometry
import Testing

@testable import Model

@Suite("Content bounds and open camera")
struct ContentBoundsTests {
    @Test("An empty canvas has no bounds and opens on the origin at zoom 1")
    func empty() {
        let content = CanvasContent(canvasID: Fixtures.canvas)
        #expect(content.contentBounds == nil)
        #expect(content.openCamera == Camera(center: .zero, zoom: Limits.standardZoom))
    }

    @Test("The bounds hold the strokes, the card frames, and the text box origins")
    func bounds() throws {
        var rig = CommandRig()
        let strokes = try rig.load(1)
        let frame = Rect(
            origin: Point(x: 1_000_000, y: 1_000_000),
            size: Size(width: 64, height: 48)
        )
        try rig.content.add(RecordTests.card(frame: frame))
        try rig.content.add(RecordTests.textBox(text: "x", origin: Point(x: -50, y: -20)))
        let bounds = try #require(rig.content.contentBounds)
        #expect(bounds.minX == -50)
        #expect(bounds.minY == -20)
        #expect(bounds.maxX == frame.maxX)
        #expect(bounds.maxY == frame.maxY)
        #expect(bounds.maxX >= strokes[0].bounds.maxX)
        #expect(rig.content.openCamera.center == bounds.center)
        #expect(rig.content.openCamera.zoom == Limits.standardZoom)
    }
}
