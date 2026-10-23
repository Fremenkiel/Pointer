import Geometry
import Testing

@testable import Export

@Suite("Page size and scale of a PDF")
struct PageLayoutTests {
    /// The longer sides of task 2.2: small, the limit, the limit plus one, and far over it.
    static let longerSides = [3.0, 14_400, 14_401, 2_000_000]

    @Test("The longer side fits the page limit", arguments: longerSides, [true, false])
    func longerSideFits(longer: Double, isWide: Bool) {
        let shorter = longer / 4
        let size =
            isWide
            ? Size(width: longer, height: shorter) : Size(width: shorter, height: longer)
        let layout = PDFExporter.pageLayout(for: Rect(origin: Point(x: -7, y: 9), size: size))
        let limit = PDFExporter.maxPageSide
        let expectedScale = longer > limit ? limit / longer : 1
        #expect(layout.scale == expectedScale)
        #expect(layout.width <= limit && layout.height <= limit)
        let pageLonger = max(layout.width, layout.height)
        #expect(abs(pageLonger - min(longer, limit)) < 1e-9)
        #expect(abs(layout.width / layout.height - size.width / size.height) < 1e-9)
        #expect(isWide ? layout.width > layout.height : layout.height > layout.width)
    }

    @Test("The page limit is 200 inches")
    func limitIsTwoHundredInches() {
        #expect(PDFExporter.maxPageSide == 200 * 72)
    }
}
