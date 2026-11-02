import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The eraser size that the user picks in the palette (TOOL-04, D-128, D-201).
@MainActor
@Suite("Eraser size")
struct EraserSizeTests {
    /// The view y of the line in the view of 400 x 300 points at the standard camera.
    private static let lineY = 150.0
    /// Half the width of the line: the reach of the eraser is its radius plus this (4.4).
    private static let halfWidth = 1.0

    /// A view of 400 x 300 points at the standard camera with one horizontal line through the
    /// canvas origin, so view (200, 150) is canvas (0, 0).
    private func makeController(settings: EraserSettings) throws -> CanvasViewController {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        try content.add(Self.line(clock: Fixtures.clock()))
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.repository = RecordingLibrary()
        dependencies.eraserSettings = settings
        let controller = CanvasViewController(dependencies: dependencies)
        controller.isShownCanvas = true
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        controller.select(.eraser)
        return controller
    }

    /// A horizontal line of width 2 from canvas (-50, 0) to (50, 0).
    private static func line(clock: AppClock) -> Stroke {
        let points = (0...50).map { InkPoint(x: Float($0) * 2, y: 0, force: 1, time: 0) }
        return Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: Fixtures.canvas,
            created: clock.now(),
            origin: Point(x: -50, y: 0),
            width: Float(halfWidth * 2),
            points: InkPoints(points)
        )
    }

    /// Runs one eraser gesture along the middle of the line, from view x 190 to 210, `distance`
    /// view points below the line. A cut leaves the two ends of the line as parts.
    private func erase(_ controller: CanvasViewController, distance: Double) {
        controller.pencilBegan()
        for step in 0...2 {
            let location = Point(x: 190 + Double(step) * 10, y: Self.lineY + distance)
            controller.pencilMoved(to: location)
        }
        controller.pencilEnded(at: 0, isCancelled: false)
    }

    @Test("A launch starts with the standard size of D-128, and the sizes are 4, 8, and 16")
    func sizes() {
        #expect(EraserSettings().size == .standard)
        #expect(EraserSize.allCases.map(\.viewPoints) == [4, 8, 16])
        #expect(EraserSize.standard.viewPoints == 8)
        #expect(EraserTool.canvasRadius(viewPoints: 16, zoom: 2) == 8)
        #expect(EraserTool.canvasRadius(viewPoints: 4, zoom: 0.5) == 8)
    }

    @Test(
        "Each size cuts a stroke inside its radius and leaves a stroke beyond it",
        arguments: EraserSize.allCases
    )
    func reach(size: EraserSize) throws {
        let settings = EraserSettings()
        settings.size = size
        let beyond = try makeController(settings: settings)
        erase(beyond, distance: size.viewPoints + Self.halfWidth + 1)
        #expect(beyond.content.strokes.count == 1, "A path beyond the reach cuts nothing")
        #expect(beyond.eraseRadius == size.viewPoints)
        let inside = try makeController(settings: settings)
        erase(inside, distance: size.viewPoints - 1)
        #expect(inside.content.strokes.count == 2, "A path inside the reach cuts the line")
    }

    @Test("A picked size reaches the hover ring and the palette of the canvas at once")
    func pick() throws {
        let controller = try makeController(settings: EraserSettings())
        controller.hoverBegan(at: CGPoint(x: 100, y: 100), isPreviewOn: true)
        controller.toolControls.selectEraserSize(.small)
        #expect(controller.eraserSettings.size == .small)
        #expect(controller.toolControls.eraserSize == .small)
        #expect(controller.canvasView.hoverDot.shownRingRadius == 4)
        controller.select(eraserSize: .large)
        #expect(controller.toolControls.eraserSize == .large)
        #expect(controller.canvasView.hoverDot.shownRingRadius == 16)
    }

    @Test("Every canvas of the app takes the picked size at its next erase")
    func sharedSettings() throws {
        let settings = EraserSettings()
        let first = try makeController(settings: settings)
        let second = try makeController(settings: settings)
        first.select(eraserSize: .large)
        #expect(second.toolControls.eraserSize == .standard, "The palette syncs at its open")
        erase(second, distance: 12)
        #expect(second.eraseRadius == EraserSize.large.viewPoints)
        #expect(second.content.strokes.count == 2)
    }

    @Test("A size picked during an erase takes effect at the next gesture (D-70)")
    func duringGesture() throws {
        let controller = try makeController(settings: EraserSettings())
        controller.pencilBegan()
        controller.pencilMoved(to: Point(x: 190, y: Self.lineY + 12))
        controller.select(eraserSize: .large)
        controller.pencilMoved(to: Point(x: 210, y: Self.lineY + 12))
        controller.pencilEnded(at: 0, isCancelled: false)
        #expect(controller.eraseRadius == EraserSize.standard.viewPoints)
        #expect(controller.content.strokes.count == 1, "The running gesture keeps its size")
        erase(controller, distance: 12)
        #expect(controller.eraseRadius == EraserSize.large.viewPoints)
        #expect(controller.content.strokes.count == 2)
    }

    @Test("Each size has a name for VoiceOver")
    func labels() {
        let labels = EraserSize.allCases.map(\.label)
        #expect(Set(labels).count == EraserSize.allCases.count)
        #expect(labels.allSatisfy { !$0.isEmpty })
    }
}
