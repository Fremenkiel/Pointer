import CoreGraphics
import Foundation
import Geometry
import Model
import PDFKit
import Testing

@testable import Export

@Suite("Text of a PDF")
struct PDFTextTests {
    @Test("A search finds each word of each text box")
    func searchFindsEachWord() throws {
        let first = "let tree = buildTree(from: nodes)\nreturn tree.depth"
        let second = String(repeating: "balanced ", count: 30) + "rotation"
        let content = try ExportContent.content(
            textBoxes: [
                ExportContent.textBox(first, at: Point(x: 0, y: 0)),
                ExportContent.textBox(second, at: Point(x: 0, y: 200)),
            ]
        )
        let document = try #require(try Self.document(of: content))
        let words = [
            "let", "tree", "buildTree(from:", "nodes)", "return", "tree.depth", "rotation",
        ]
        for word in words {
            #expect(!document.findString(word, withOptions: []).isEmpty, "\(word)")
        }
        let text = try #require(document.page(at: 0)?.string)
        #expect(text.components(separatedBy: "balanced").count - 1 == 30)
    }

    @Test("A text with emoji and CJK keeps its letters")
    func emojiAndCJKKeepTheirLetters() throws {
        let text = "tree 🌳 node 漢字かな 한글 leaf"
        let content = try ExportContent.content(
            textBoxes: [ExportContent.textBox(text, at: Point(x: 0, y: 0))]
        )
        let document = try #require(try Self.document(of: content))
        let pageText = try #require(document.page(at: 0)?.string)
        for word in ["tree", "🌳", "node", "漢字かな", "한글", "leaf"] {
            #expect(pageText.contains(word), "\(word)")
        }
        #expect(!document.findString("leaf", withOptions: []).isEmpty)
    }

    @Test("The lines sit at the baselines of the layout, top to bottom")
    func linesAreInOrder() throws {
        let content = try ExportContent.content(
            textBoxes: [ExportContent.textBox("alpha\nbravo\ncharlie", at: Point(x: 0, y: 0))]
        )
        let document = try #require(try Self.document(of: content))
        let page = try #require(document.page(at: 0))
        let alpha = try #require(document.findString("alpha", withOptions: []).first)
        let charlie = try #require(document.findString("charlie", withOptions: []).first)
        // PDF y grows up, so the first line has the larger y.
        #expect(alpha.bounds(for: page).minY > charlie.bounds(for: page).minY)
    }

    @Test("The page writes its text boxes top to bottom, then left to right (D-185)")
    func pageOrder() throws {
        let boxes = [
            try ExportContent.textBox("lower left", at: Point(x: 0, y: 100)),
            try ExportContent.textBox("upper right", at: Point(x: 200, y: 0)),
            try ExportContent.textBox("upper left", at: Point(x: 0, y: 0)),
            try ExportContent.textBox("lower right", at: Point(x: 200, y: 100)),
        ]
        let content = try ExportContent.content(textBoxes: boxes)
        let order = PDFExporter.pageOrder(of: content.textBoxes.values).map(\.text)
        #expect(order == ["upper left", "upper right", "lower left", "lower right"])
    }

    /// Draws the text of the content on a flipped page of 1,000 by 1,000 points, as the exporter
    /// does, and reads the PDF back.
    private static func document(of content: CanvasContent) throws -> PDFDocument? {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return nil }
        context.beginPDFPage(nil)
        context.translateBy(x: 0, y: box.height)
        context.scaleBy(x: 1, y: -1)
        try PDFExporter.drawText(of: content, from: Point(x: -50, y: -50), in: context)
        context.endPDFPage()
        context.closePDF()
        return PDFDocument(data: data as Data)
    }
}
