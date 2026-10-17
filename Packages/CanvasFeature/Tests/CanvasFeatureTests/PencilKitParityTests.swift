import Geometry
import Model
import PencilKit
import Rendering
import Testing

@testable import CanvasFeature

@MainActor
@Suite("PencilKit parity")
struct PencilKitParityTests {
    private let viewSize = Size(width: 200, height: 120)

    @Test("StrokeCurve matches PKStrokePath.interpolatedLocation within 0.01 points (acceptance 9)")
    func curveMatchesPencilKit() {
        var random = SeededRandom(state: 11)
        for count in [2, 3, 4, 7, 50] {
            let points = (0..<count).map { _ in
                CGPoint(
                    x: Double.random(in: -500...500, using: &random),
                    y: Double.random(in: -500...500, using: &random)
                )
            }
            let path = Fixtures.pencilKitStroke(points, pointSize: 3).path
            let curve = StrokeCurve(controlPoints: points.map { Point(x: $0.x, y: $0.y) })
            let steps = (count - 1) * 16
            for step in 0...steps {
                let parameter = Double(step) / 16
                let expected = path.interpolatedLocation(at: CGFloat(parameter))
                let actual = curve.point(at: parameter)
                #expect(abs(actual.x - expected.x) < 0.01 && abs(actual.y - expected.y) < 0.01)
            }
        }
    }

    @Test(
        "A monoline point of size s draws 2 (s - 2) points wide",
        arguments: [2.5, 3.0, 4.0, 10.0]
    )
    func monolineWidth(pointSize: Double) throws {
        let stroke = Fixtures.pencilKitStroke(
            [CGPoint(x: 20, y: 60), CGPoint(x: 180, y: 60)],
            pointSize: pointSize
        )
        let image = try #require(
            Fixtures.pencilKitImage(
                PKDrawing(strokes: [stroke]),
                size: CGSize(width: 200, height: 120),
                scale: 2
            )
        )
        let column = (0..<image.height).reduce(0) { $0 + Int(image.gray(x: 200, y: $1)) }
        let width = Double(column) / 255 / 2
        #expect(abs(width - PencilKitStrokeConverter.drawnWidth(pointSize: pointSize)) < 0.05)
    }

    @Test("The center of a PencilKit stroke is 255 in each channel (acceptance 6)")
    func pencilKitWhite() throws {
        let stroke = Fixtures.pencilKitStroke(
            [CGPoint(x: 20, y: 60), CGPoint(x: 180, y: 60)],
            pointSize: 4
        )
        let image = try #require(
            Fixtures.pencilKitImage(
                PKDrawing(strokes: [stroke]),
                size: CGSize(width: 200, height: 120),
                scale: 2
            )
        )
        let base = (120 * image.width + 200) * 4
        #expect(Array(image.pixels[base..<base + 3]) == [255, 255, 255])
    }

    @Test(
        "The Metal stroke matches the PencilKit stroke at the handoff (acceptance 4)",
        arguments: [0.25, 1.0, 8.0]
    )
    func handoffImage(zoom: Double) throws {
        let pointSize = PencilKitStrokeConverter.pointSize(drawingWidth: PenTool.width * zoom)
        let live = Fixtures.pencilKitStroke(Fixtures.wave(), pointSize: pointSize)
        let camera = Camera(center: Point(x: 1_000, y: -2_000), zoom: zoom)
        var converter = PencilKitStrokeConverter(
            factory: Fixtures.factory(),
            canvasID: Fixtures.canvas
        )
        let strokes = try converter.convert(live, camera: camera, viewSize: viewSize)
        let renderer = try CanvasRenderer()
        let metal = try renderer.renderImage(
            of: strokes,
            camera: camera,
            viewSize: viewSize,
            displayScale: 2
        )
        let pencilKit = try #require(
            Fixtures.pencilKitImage(
                PKDrawing(strokes: [live]),
                size: CGSize(width: 200, height: 120),
                scale: 2
            )
        )
        let comparison = InkComparison(metal, pencilKit)
        #expect(abs(comparison.inkRatio - 1) < 0.03, "Ink ratio \(comparison.inkRatio)")
        #expect(comparison.differingPixels == 0, "\(comparison)")
        #expect(comparison.maxDifference <= 32, "\(comparison)")
    }
}
