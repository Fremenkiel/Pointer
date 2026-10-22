import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The hover dot of the pen and the eraser circle on the canvas view (PEN-04, D-128, D-133,
/// TEST-07). `ViewSnapshot` comes from the selector snapshots, which `PointerDeviceTests`
/// compiles in the same target.
@MainActor
@Suite("Hover dot snapshots")
struct HoverDotSnapshotTests {
    /// The side of the canvas view in view points: room for the eraser circle and a margin.
    private static let side = 32.0

    @Test("The pen shows a small gray dot at the tip")
    func penDot() throws {
        try ViewSnapshot.assertMatches(image: render(tool: .pen), named: "hover-dot-pen")
    }

    @Test("The eraser shows a gray outline circle with the eraser radius")
    func eraserCircle() throws {
        try ViewSnapshot.assertMatches(image: render(tool: .eraser), named: "hover-dot-eraser")
    }

    /// Renders the canvas view of a shown canvas with `tool` while the pencil hovers over its
    /// center. The Metal layer of the ink draws nothing in a `CGContext`, so the image holds the
    /// canvas color and the dot.
    private func render(tool: Tool) throws -> UIImage {
        let canvas = CanvasViewController(
            dependencies: CanvasDependencies(
                renderer: try CanvasRenderer(),
                clock: Fixtures.clock(),
                content: CanvasContent(canvasID: Fixtures.canvas)
            )
        )
        canvas.isShownCanvas = true
        let size = CGSize(width: Self.side, height: Self.side)
        canvas.view.frame = CGRect(origin: .zero, size: size)
        canvas.view.layoutIfNeeded()
        canvas.select(tool)
        canvas.hoverBegan(at: CGPoint(x: size.width / 2, y: size.height / 2), isPreviewOn: true)
        #expect(canvas.canvasView.hoverDot.shownCenter != nil)
        let format = UIGraphicsImageRendererFormat()
        format.scale = ViewSnapshot.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            canvas.canvasView.layer.render(in: context.cgContext)
        }
    }
}
