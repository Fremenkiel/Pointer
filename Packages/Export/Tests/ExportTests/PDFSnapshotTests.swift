import Geometry
import Model
import Testing

@testable import Export

/// The rendered page of an exported PDF (M8 acceptance 2, TEST-07).
@Suite("PDF page snapshot")
struct PDFSnapshotTests {
    @Test("The page is white with black ink and text, and shows no card")
    func pageSnapshot() throws {
        let data = try PDFExporter.pdfData(of: try PDFExporterTests.mixedContent())
        let image = try #require(PDFRender.image(of: data, scale: 2))
        #expect(image.gray(x: 0, y: 0) == 255)
        Snapshot.assertMatches(image, named: "pdf-page")
    }
}
