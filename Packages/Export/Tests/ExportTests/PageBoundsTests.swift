import Geometry
import Model
import Rendering
import Testing

@testable import Export

@Suite("Page bounds of a PDF")
struct PageBoundsTests {
    @Test("The bounds of strokes are their union plus the margin")
    func strokesOnly() throws {
        let first = ExportContent.wave(count: 20, at: Point(x: -100, y: 40), width: 4)
        let second = ExportContent.wave(count: 5, at: Point(x: 300, y: -250))
        let content = try ExportContent.content(strokes: [first, second])
        let bounds = try #require(PDFExporter.pageBounds(of: content))
        let margin = PDFExporter.margin
        #expect(bounds.minX == first.bounds.minX - margin)
        #expect(bounds.maxX == second.bounds.maxX + margin)
        #expect(bounds.minY == second.bounds.minY - margin)
        #expect(bounds.maxY == first.bounds.maxY + margin)
    }

    @Test("The bounds of a text box hold its full layout plus the margin")
    func textOnly() throws {
        let text = String(repeating: "node ", count: 60)
        let box = try ExportContent.textBox(text, at: Point(x: 10, y: 20))
        let content = try ExportContent.content(textBoxes: [box])
        let bounds = try #require(PDFExporter.pageBounds(of: content))
        let size = TextLayout(text: text).size
        #expect(size.height > TextLayout.lineHeight)
        #expect(bounds.minX == 10 - PDFExporter.margin)
        #expect(bounds.minY == 20 - PDFExporter.margin)
        #expect(bounds.maxX == 10 + size.width + PDFExporter.margin)
        #expect(bounds.maxY == 20 + size.height + PDFExporter.margin)
    }

    @Test("The bounds of strokes and text hold both")
    func strokesAndText() throws {
        let stroke = ExportContent.wave(count: 10, at: Point(x: 0, y: 0))
        let box = try ExportContent.textBox("leaf", at: Point(x: 500, y: 400))
        let content = try ExportContent.content(strokes: [stroke], textBoxes: [box])
        let bounds = try #require(PDFExporter.pageBounds(of: content))
        let size = TextLayout(text: "leaf").size
        #expect(bounds.minX == stroke.bounds.minX - PDFExporter.margin)
        #expect(bounds.minY == stroke.bounds.minY - PDFExporter.margin)
        #expect(bounds.maxX == 500 + size.width + PDFExporter.margin)
        #expect(bounds.maxY == 400 + size.height + PDFExporter.margin)
    }

    @Test("Cards do not count")
    func cardsDoNotCount() throws {
        let card = try ExportContent.card(
            title: "Far",
            frame: Rect(origin: Point(x: 5_000, y: 5_000), size: Size(width: 100, height: 70))
        )
        let stroke = ExportContent.wave(count: 10, at: Point(x: 0, y: 0))
        let content = try ExportContent.content(strokes: [stroke], cards: [card])
        let bounds = try #require(PDFExporter.pageBounds(of: content))
        #expect(bounds.maxX == stroke.bounds.maxX + PDFExporter.margin)
    }

    @Test("A canvas with only cards and an empty canvas have no page", arguments: [true, false])
    func emptyCanvasHasNoPage(hasCard: Bool) throws {
        let card = try ExportContent.card(
            title: "Only",
            frame: Rect(origin: .zero, size: Size(width: 100, height: 70))
        )
        let content = try ExportContent.content(cards: hasCard ? [card] : [])
        #expect(PDFExporter.pageBounds(of: content) == nil)
    }

    @Test("A stroke far from the origin keeps its bounds")
    func farStroke() throws {
        let stroke = ExportContent.wave(count: 10, at: Point(x: 1_000_000, y: 1_000_000))
        let content = try ExportContent.content(strokes: [stroke])
        let bounds = try #require(PDFExporter.pageBounds(of: content))
        #expect(bounds == stroke.bounds.expanded(by: PDFExporter.margin))
        #expect(bounds.minX > 999_900)
    }
}
