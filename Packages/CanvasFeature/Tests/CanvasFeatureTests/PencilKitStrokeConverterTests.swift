import Geometry
import Model
import PencilKit
import Testing
import UIKit

@testable import CanvasFeature

@MainActor
@Suite("PencilKit stroke converter")
struct PencilKitStrokeConverterTests {
    private let viewSize = Size(width: 1000, height: 800)

    @Test("A stroke converts to canvas space with the camera and the drawn width")
    func conversion() throws {
        let live = Fixtures.pencilKitStroke(
            [CGPoint(x: 500, y: 400), CGPoint(x: 520, y: 400)],
            pointSize: 6
        )
        let camera = Camera(center: Point(x: 1_000_000, y: 1_000_000), zoom: 4)
        let converter = PencilKitStrokeConverter(
            clock: Fixtures.clock(),
            canvasID: Fixtures.canvas
        )
        let converted = try converter.convert(live, camera: camera, viewSize: viewSize)
        let stroke = try #require(converted.first)
        #expect(stroke.origin == Point(x: 1_000_000, y: 1_000_000))
        #expect(stroke.canvasPoint(at: 1) == Point(x: 1_000_005, y: 1_000_000))
        #expect(stroke.width == 2)
        #expect(stroke.canvasID == Fixtures.canvas)
    }

    @Test("The stroke transform applies before the camera")
    func strokeTransform() throws {
        var live = Fixtures.pencilKitStroke(
            [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)],
            pointSize: 3
        )
        live.transform = CGAffineTransform(translationX: 500, y: 400)
        let converter = PencilKitStrokeConverter(
            clock: Fixtures.clock(),
            canvasID: Fixtures.canvas
        )
        let converted = try converter.convert(
            live,
            camera: Camera(center: .zero, zoom: 1),
            viewSize: viewSize
        )
        let stroke = try #require(converted.first)
        #expect(stroke.origin == .zero)
        #expect(stroke.canvasPoint(at: 1) == Point(x: 10, y: 0))
    }

    @Test("A path above the point limit becomes several strokes")
    func split() throws {
        let points = (0...Limits.maxPointsPerStroke).map { CGPoint(x: Double($0) * 0.01, y: 0) }
        let live = Fixtures.pencilKitStroke(points, pointSize: 3)
        let converter = PencilKitStrokeConverter(
            clock: Fixtures.clock(),
            canvasID: Fixtures.canvas
        )
        let strokes = try converter.convert(
            live,
            camera: Camera(center: .zero, zoom: 1),
            viewSize: viewSize
        )
        #expect(strokes.count == 2)
        #expect(strokes.allSatisfy { $0.points.count <= Limits.maxPointsPerStroke })
    }

    @Test("A path that PencilKit does not draw falls back to the pen width")
    func fallbackWidth() throws {
        let live = Fixtures.pencilKitStroke(
            [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)],
            pointSize: 1
        )
        #expect(PencilKitStrokeConverter.drawnWidth(of: live.path) == nil)
        let converter = PencilKitStrokeConverter(
            clock: Fixtures.clock(),
            canvasID: Fixtures.canvas
        )
        let converted = try converter.convert(
            live,
            camera: Camera(center: .zero, zoom: 2),
            viewSize: viewSize
        )
        let stroke = try #require(converted.first)
        #expect(Double(stroke.width) == PenTool.width)
    }

    @Test("The width rule and its inverse agree", arguments: [0.5, 2.0, 16.0])
    func inverse(width: Double) {
        let size = PencilKitStrokeConverter.pointSize(drawingWidth: width)
        #expect(abs(PencilKitStrokeConverter.drawnWidth(pointSize: size) - width) < 1e-12)
    }

    @Test("The live tool is a white monoline with the pen width times the zoom")
    @MainActor
    func tool() {
        let tool = PenTool.inkingTool(zoom: 4)
        #expect(tool.inkType == .monoline)
        #expect(tool.width == 8)
        let white = tool.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(white.cgColor.components == [1, 1, 1, 1])
    }
}
