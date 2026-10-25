import CoreGraphics
import Geometry
import Model

extension PDFExporter {
    /// Returns the path of a stroke: one move and one cubic Bézier segment per piece of its
    /// B-spline (D-26, EXP-02).
    ///
    /// Each point is relative to `pageOrigin` in `Double` before it becomes a `CGFloat`, so a
    /// stroke far from the canvas origin keeps its shape (M2 acceptance 3).
    ///
    /// - Precondition: `pageOrigin` is finite.
    /// - Returns: A path with one move and `count - 1` curves, in canvas points from
    ///   `pageOrigin`.
    static func path(of stroke: Stroke, from pageOrigin: Point) -> CGPath {
        precondition(pageOrigin.isFinite, "Page origin of stroke \(stroke.id) is not finite")
        let relative = stroke.points.values.indices.map { index in
            let offset = stroke.canvasPoint(at: index) - pageOrigin
            return Point(x: offset.dx, y: offset.dy)
        }
        let curve = StrokeCurve(controlPoints: relative)
        let path = CGMutablePath()
        path.move(to: cgPoint(curve.bezierSegment(at: 0).start))
        for index in 0..<curve.segmentCount {
            let segment = curve.bezierSegment(at: index)
            path.addCurve(
                to: cgPoint(segment.end),
                control1: cgPoint(segment.control1),
                control2: cgPoint(segment.control2)
            )
        }
        return path
    }

    /// The strokes between two checks for a cancel: a check costs an atomic read.
    static let cancelCheckStrokes = 1_024

    /// Draws each stroke of the content in black, with its width and round caps and joins.
    ///
    /// - Precondition: `pageOrigin` is finite.
    /// - Throws: `ExportError.cancelled` if the task is cancelled.
    static func drawStrokes(
        of content: CanvasContent,
        from pageOrigin: Point,
        in context: CGContext
    ) throws(ExportError) {
        precondition(pageOrigin.isFinite, "Page origin of \(content.canvasID) is not finite")
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for (index, stroke) in content.strokes.values.enumerated() {
            // A closed canvas cancels its export, which can hold 1 GB of points for 17 s.
            if index.isMultiple(of: cancelCheckStrokes), Task.isCancelled { throw .cancelled }
            context.addPath(path(of: stroke, from: pageOrigin))
            context.setLineWidth(CGFloat(stroke.width))
            context.strokePath()
        }
        assert(context.isPathEmpty, "The strokes of \(content.canvasID) leave no open path")
    }

    /// Converts a point to Core Graphics.
    private static func cgPoint(_ point: Point) -> CGPoint {
        CGPoint(x: point.x, y: point.y)
    }
}
