import Foundation
import Geometry
import Model

/// The content of the performance tests (docs/m2-fix-plan.md section 1).
enum PerformanceContent {
    /// The columns of the stroke grid of the dense content.
    private static let denseColumns = 200
    /// The columns of the stroke grid of the handwriting content.
    private static let handwritingColumns = 100
    /// The length of a dense stroke in x, in canvas points.
    private static let denseLength = 24.0
    /// The control points of one handwriting stroke.
    static let handwritingPoints = 60

    /// The strokes of the M2 content-pass tests: `points` control points 0.08 canvas points apart
    /// in x with a wave of 4 canvas points in y, in a grid of 30 by 30 canvas points. The wave puts
    /// neighbor points up to 0.8 canvas points apart.
    ///
    /// - Precondition: `points >= 2`.
    static func m2Dense(count: Int, points: Int) -> [Stroke] {
        precondition(points >= 2, "A stroke has 2 points at least, got \(points)")
        return (0..<count).map { index in
            let origin = denseOrigin(index)
            let path = (0..<points).map { step in
                Point(x: origin.x + Double(step) * 0.08, y: origin.y + sin(Double(step) * 0.2) * 4)
            }
            return StrokeBuilder.stroke(path, seed: index)
        }
    }

    /// Dense strokes of the benchmark of docs/m2-fix-plan.md section 1: `points` control points
    /// on a smooth curve 24 canvas points long, in the grid of the M2 content.
    ///
    /// - Precondition: `points >= 2`.
    static func dense(count: Int, points: Int) -> [Stroke] {
        precondition(points >= 2, "A stroke has 2 points at least, got \(points)")
        let step = denseLength / Double(points - 1)
        return (0..<count).map { index in
            let origin = denseOrigin(index)
            let path = (0..<points).map { point in
                let x = Double(point) * step
                return Point(x: origin.x + x, y: origin.y + sin(x / denseLength * 6) * 4)
            }
            return StrokeBuilder.stroke(path, seed: index)
        }
    }

    private static func denseOrigin(_ index: Int) -> Point {
        let column = Double(index % denseColumns)
        let row = Double(index / denseColumns)
        return Point(x: column * 30 - 3000, y: row * 30 - 1500)
    }

    /// Handwriting: strokes of 60 control points about 2 canvas points apart, 120 canvas points
    /// long. This is closer to real pencil input at 240 Hz than the dense content.
    static func handwriting(count: Int) -> [Stroke] {
        (0..<count).map { index in
            let column = Double(index % handwritingColumns)
            let row = Double(index / handwritingColumns)
            let origin = Point(x: column * 140 - 7000, y: row * 40 - 4000)
            let path = (0..<handwritingPoints).map { step in
                let t = Double(step)
                return Point(
                    x: origin.x + t * 2,
                    y: origin.y + sin(t * 0.7 + Double(index)) * 9
                )
            }
            return StrokeBuilder.stroke(path, seed: index)
        }
    }
}
