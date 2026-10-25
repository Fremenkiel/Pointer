import Geometry
import Model
import PencilKit

/// Turns a finished `PKStroke` into strokes of the model (architecture.md 4.2).
///
/// It reads the control points of `stroke.path` (D-26) and the transforms. The math lives in
/// `Geometry` and `Model`: `StrokeFactory` applies the transforms and splits a long path.
struct PencilKitStrokeConverter {
    /// The smallest point size that PencilKit draws. A monoline point of size `s` draws a line
    /// `2 * (s - 2)` points wide (docs/m2-plan.md section 1, fact 2).
    static let monolineSizeOffset = 2.0

    /// The clock of the app, which makes the IDs and the clock values.
    let clock: AppClock
    /// The canvas that gets the strokes.
    let canvasID: CanvasID

    /// Converts a stroke that the live `PKCanvasView` drew at zoom 1 in view space.
    ///
    /// - Throws: `ModelError` if the path has no points or a value that is not finite.
    /// - Returns: One stroke, or several strokes for a path above the point limit.
    @MainActor
    func convert(
        _ stroke: PKStroke,
        camera: Camera,
        viewSize: Size
    ) throws(ModelError) -> [Stroke] {
        let samples = stroke.path.map { point in
            ControlPointSample(
                location: Point(x: Double(point.location.x), y: Double(point.location.y)),
                force: Double(point.force),
                timeOffset: point.timeOffset
            )
        }
        guard !samples.isEmpty else { throw .emptyPath }
        let width = Self.drawnWidth(of: stroke.path) ?? PenTool.width * camera.zoom
        let toCanvas = Self.transform(stroke.transform).then(
            camera.viewToCanvas(viewSize: viewSize)
        )
        let path = PenPath(samples: samples, toCanvas: toCanvas, width: width)
        let strokes = try clock.factory.makeStrokes(from: path, canvasID: canvasID)
        assert(!strokes.isEmpty, "A path with samples gives a stroke")
        return strokes
    }

    /// Returns the width that PencilKit drew, in the units of the path, from the point sizes.
    ///
    /// - Returns: `nil` if the path has no point that PencilKit draws.
    static func drawnWidth(of path: PKStrokePath) -> Double? {
        guard !path.isEmpty else { return nil }
        let total = path.reduce(0.0) { $0 + drawnWidth(pointSize: Double($1.size.width)) }
        let mean = total / Double(path.count)
        guard mean > 0, mean.isFinite else { return nil }
        return mean
    }

    /// Returns the drawn width of one monoline point size (fact 2).
    static func drawnWidth(pointSize: Double) -> Double {
        max(0, 2 * (pointSize - monolineSizeOffset))
    }

    // Only the tests read it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// Returns the point size that draws a line of `width` points (the inverse of fact 2).
    ///
    /// - Precondition: `width` is positive.
    static func pointSize(drawingWidth width: Double) -> Double {
        // swiftlint:enable unused_declaration
        precondition(width > 0, "Width must be positive, got \(width)")
        return width / 2 + monolineSizeOffset
    }

    /// Returns the `Transform` of a `CGAffineTransform`.
    static func transform(_ affine: CGAffineTransform) -> Transform {
        Transform(
            a: Double(affine.a),
            b: Double(affine.b),
            c: Double(affine.c),
            d: Double(affine.d),
            tx: Double(affine.tx),
            ty: Double(affine.ty)
        )
    }
}
