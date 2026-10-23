import CoreGraphics
import Geometry
import Model
import Testing

@testable import Export

@Suite("Stroke paths of a PDF")
struct StrokePathTests {
    @Test("A stroke gives one move and one curve per segment", arguments: [2, 300])
    func moveAndCurves(count: Int) throws {
        let stroke = ExportContent.wave(count: count, at: Point(x: 40, y: 60))
        let origin = Point(x: 10, y: 20)
        let elements = PathElements.of(PDFExporter.path(of: stroke, from: origin))
        #expect(elements.count == count)
        #expect(elements.filter { $0.kind == .moveToPoint }.count == 1)
        #expect(elements.filter { $0.kind == .addCurveToPoint }.count == count - 1)
        let first = try #require(elements.first?.points.first)
        let last = try #require(elements.last?.points.last)
        let start = stroke.canvasPoint(at: 0) - origin
        let end = stroke.canvasPoint(at: count - 1) - origin
        #expect(abs(first.x - start.dx) < 1e-9 && abs(first.y - start.dy) < 1e-9)
        #expect(abs(last.x - end.dx) < 1e-9 && abs(last.y - end.dy) < 1e-9)
    }

    @Test("A stroke far from the origin keeps its shape")
    func farStrokeKeepsItsShape() {
        let offset = 1_000_000.0
        let near = ExportContent.wave(count: 300, at: Point(x: 0, y: 0))
        let far = ExportContent.wave(count: 300, at: Point(x: offset, y: offset))
        let nearElements = PathElements.of(
            PDFExporter.path(of: near, from: Point(x: -48, y: -48))
        )
        let farElements = PathElements.of(
            PDFExporter.path(of: far, from: Point(x: offset - 48, y: offset - 48))
        )
        #expect(nearElements.count == farElements.count)
        var largest = 0.0
        for (nearElement, farElement) in zip(nearElements, farElements) {
            #expect(nearElement.kind == farElement.kind)
            for (a, b) in zip(nearElement.points, farElement.points) {
                largest = max(largest, abs(a.x - b.x), abs(a.y - b.y))
            }
        }
        #expect(largest < 1e-6, "The largest difference is \(largest)")
    }
}
