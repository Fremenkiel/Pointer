import Geometry
import Model
import PencilKit
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The pen width that the user picks in the palette (TOOL-02, TOOL-09, D-199).
@MainActor
@Suite("Pen width")
struct PenWidthTests {
    private let viewSize = Size(width: 200, height: 120)

    /// A shown canvas at zoom 2 with the given pen settings.
    private func makeController(settings: PenSettings) throws -> CanvasViewController {
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: CanvasContent(canvasID: Fixtures.canvas)
        )
        dependencies.camera = Camera(center: .zero, zoom: 2)
        dependencies.penSettings = settings
        let controller = CanvasViewController(dependencies: dependencies)
        controller.loadViewIfNeeded()
        return controller
    }

    /// The width of the pen tool of the live canvas.
    private func toolWidth(of controller: CanvasViewController) throws -> CGFloat {
        try #require(controller.canvasView.liveCanvas.tool as? PKInkingTool).width
    }

    @Test("A launch starts with the standard width of D-37, and the widths are 1, 2, and 4")
    func widths() {
        #expect(PenSettings().width == .standard)
        #expect(PenWidth.allCases.map(\.canvasPoints) == [1, 2, 4])
        #expect(PenWidth.standard.canvasPoints == 2)
    }

    @Test(
        "The live tool is a white monoline with the width times the zoom",
        arguments: PenWidth.allCases
    )
    func tool(width: PenWidth) {
        let tool = PenTool.inkingTool(width: width, zoom: 4)
        #expect(tool.inkType == .monoline)
        // PencilKit on the iPad gives the width of 16 back with a rounding error below 0.001.
        let difference = abs(Double(tool.width) - width.canvasPoints * 4)
        #expect(difference < 0.001, "Tool width \(tool.width) for \(width)")
        let white = tool.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(white.cgColor.components == [1, 1, 1, 1])
    }

    @Test("A picked width reaches the live pen at once and the palette of the canvas")
    func pick() throws {
        let controller = try makeController(settings: PenSettings())
        #expect(try toolWidth(of: controller) == 4)
        controller.toolControls.selectWidth(.thick)
        #expect(try toolWidth(of: controller) == 8)
        #expect(controller.toolControls.penWidth == .thick)
        #expect(controller.penSettings.width == .thick)
        controller.select(width: .thin)
        #expect(try toolWidth(of: controller) == 2)
        #expect(controller.toolControls.penWidth == .thin)
    }

    @Test("Every canvas of the app takes the picked width at its next pencil down")
    func sharedSettings() throws {
        let settings = PenSettings()
        let first = try makeController(settings: settings)
        let second = try makeController(settings: settings)
        first.select(width: .thick)
        #expect(try toolWidth(of: second) == 4, "The second canvas waits for a touch")
        second.pencilBegan()
        #expect(try toolWidth(of: second) == 8)
        second.pencilEnded(at: 0, isCancelled: true)
        #expect(second.penSettings.width == .thick)
    }

    @Test("A width picked during a pencil touch takes effect at the next pencil down (D-70)")
    func duringTouch() throws {
        let controller = try makeController(settings: PenSettings())
        controller.pencilBegan()
        controller.select(width: .thin)
        #expect(try toolWidth(of: controller) == 4, "The running stroke keeps its width")
        #expect(controller.toolControls.penWidth == .thin)
        controller.pencilEnded(at: 0, isCancelled: true)
        controller.pencilBegan()
        #expect(try toolWidth(of: controller) == 2)
        controller.pencilEnded(at: 0, isCancelled: true)
    }

    @Test("A path that PencilKit does not draw falls back to the picked width")
    func fallbackWidth() throws {
        let live = Fixtures.pencilKitStroke(
            [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)],
            pointSize: 1
        )
        let converter = PencilKitStrokeConverter(
            clock: Fixtures.clock(),
            canvasID: Fixtures.canvas
        )
        let converted = try converter.convert(
            live,
            camera: Camera(center: .zero, zoom: 2),
            viewSize: viewSize,
            penWidth: .thick
        )
        let stroke = try #require(converted.first)
        #expect(Double(stroke.width) == PenWidth.thick.canvasPoints)
    }

    @Test("Each width has a name for VoiceOver")
    func labels() {
        let labels = PenWidth.allCases.map(\.label)
        #expect(Set(labels).count == PenWidth.allCases.count)
        #expect(labels.allSatisfy { !$0.isEmpty })
    }
}
