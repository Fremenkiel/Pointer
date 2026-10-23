import CoreGraphics
import Foundation
import Geometry
import Model
import PDFKit
import Testing

@testable import Export

@Suite("PDF exporter")
struct PDFExporterTests {
    @Test("An empty canvas and a canvas with only cards throw", arguments: [false, true])
    func emptyCanvasThrows(hasCard: Bool) throws {
        let card = try ExportContent.card(
            title: "Only",
            frame: Rect(origin: .zero, size: Size(width: 100, height: 70))
        )
        let content = try ExportContent.content(cards: hasCard ? [card] : [])
        #expect(throws: ExportError.emptyCanvas) { try PDFExporter.pdfData(of: content) }
    }

    @Test("A canvas gives one page with the media box of its page layout")
    func onePageWithTheMediaBox() throws {
        let content = try Self.mixedContent()
        let document = try #require(PDFDocument(data: try PDFExporter.pdfData(of: content)))
        #expect(document.pageCount == 1)
        let page = try #require(document.page(at: 0))
        let bounds = try #require(PDFExporter.pageBounds(of: content))
        let layout = PDFExporter.pageLayout(for: bounds)
        let box = page.bounds(for: .mediaBox)
        #expect(abs(box.width - layout.width) < 0.01 && abs(box.height - layout.height) < 0.01)
        #expect(box.origin == .zero)
    }

    @Test("The page text holds the text boxes and no card title")
    func pageTextHoldsNoCardTitle() throws {
        let text = try #require(Self.pageText(of: try Self.mixedContent()))
        #expect(text.contains("heap"))
        #expect(text.contains("sift"))
        #expect(!text.contains("Graveyard"))
    }

    @Test("The PDF of an ink-only canvas holds no image")
    func inkOnlyHoldsNoImage() throws {
        let strokes = (0..<20).map { index in
            ExportContent.wave(count: 50, at: Point(x: 0, y: Double(index) * 30))
        }
        let data = try PDFExporter.pdfData(of: try ExportContent.content(strokes: strokes))
        let page = try #require(PDFRender.firstPage(of: data))
        #expect(Self.xObjectCount(of: page) == 0)
        // The page must show the ink, or the check above tests a blank page.
        let image = try #require(PDFRender.image(of: data))
        #expect(PDFRender.darkPixelCount(of: image) > 1_000)
        #expect(image.gray(x: 0, y: 0) == 255)
    }

    @Test("A page over 14,400 points fits the limit and keeps its proportions")
    func largePageFits() throws {
        let near = ExportContent.wave(count: 10, at: Point(x: 0, y: 0))
        let far = ExportContent.wave(count: 10, at: Point(x: 40_000, y: 10_000))
        let content = try ExportContent.content(strokes: [near, far])
        let document = try #require(PDFDocument(data: try PDFExporter.pdfData(of: content)))
        let box = try #require(document.page(at: 0)?.bounds(for: .mediaBox))
        let bounds = try #require(PDFExporter.pageBounds(of: content))
        #expect(box.width <= PDFExporter.maxPageSide && box.height <= PDFExporter.maxPageSide)
        #expect(abs(box.width - PDFExporter.maxPageSide) < 0.01)
        let ratio = bounds.size.width / bounds.size.height
        #expect(abs(box.width / box.height - ratio) < 0.001)
    }

    @Test("An export off the main actor gives the same page as on the main actor")
    @MainActor
    func detachedExportMatches() async throws {
        let content = try Self.mixedContent()
        let main = try PDFExporter.pdfData(of: content)
        let detached = try await Task.detached { try PDFExporter.pdfData(of: content) }.value
        let mainPage = try #require(PDFDocument(data: main)?.page(at: 0))
        let detachedPage = try #require(PDFDocument(data: detached)?.page(at: 0))
        #expect(mainPage.string == detachedPage.string)
        #expect(mainPage.bounds(for: .mediaBox) == detachedPage.bounds(for: .mediaBox))
    }

    /// Strokes, two text boxes, and a card with the title "Graveyard".
    static func mixedContent() throws -> CanvasContent {
        try ExportContent.content(
            strokes: [
                ExportContent.wave(count: 40, at: Point(x: 0, y: 0), width: 3),
                ExportContent.wave(count: 12, at: Point(x: 60, y: 120)),
            ],
            textBoxes: [
                ExportContent.textBox("heap.push(node)", at: Point(x: 160, y: 0)),
                ExportContent.textBox("sift down\nO(log n)", at: Point(x: 160, y: 80)),
            ],
            cards: [
                ExportContent.card(
                    title: "Graveyard",
                    frame: Rect(origin: Point(x: 0, y: 200), size: Size(width: 140, height: 90))
                )
            ]
        )
    }

    /// Returns the text of the first page of the PDF of the content.
    private static func pageText(of content: CanvasContent) throws -> String? {
        PDFDocument(data: try PDFExporter.pdfData(of: content))?.page(at: 0)?.string
    }

    /// Returns the number of XObjects (images and forms) in the resources of a page.
    private static func xObjectCount(of page: CGPDFPage) -> Int {
        guard let dictionary = page.dictionary else { return -1 }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources),
            let resources
        else { return 0 }
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else {
            return 0
        }
        return CGPDFDictionaryGetCount(objects)
    }
}
