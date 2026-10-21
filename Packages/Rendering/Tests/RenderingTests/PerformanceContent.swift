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

    /// The text boxes of D-56: boxes of 200 characters on a grid of 120 by 90 canvas points, 100
    /// boxes per row, around the origin.
    static func textBoxes(count: Int) throws -> [TextBox] {
        precondition(count > 0 && count <= Limits.maxNodesPerCanvas, "Text box count \(count)")
        let device = DeviceID(rawValue: UUID())
        let canvas = CanvasID(rawValue: UUID())
        let meta = RecordMeta(created: HybridTimestamp(wallMillis: 1, counter: 0, device: device))
        let text = String(repeating: "node ", count: 40)
        let key = try FractionalIndex(rawValue: "V")
        let rows = (count + 99) / 100
        return try (0..<count).map { index in
            try TextBox(
                id: TextBoxID(rawValue: UUID()),
                meta: meta,
                canvasID: canvas,
                origin: Point(
                    x: Double(index % 100) * 120 - 6_000,
                    y: Double(index / 100) * 90 - Double(rows) * 45
                ),
                text: text,
                sortKey: key
            )
        }
    }

    /// The cards of D-56 around the origin: 100 by 70 points, in rows of 100, with the titles
    /// "Card N", as `D56Library` stores them.
    static func cards(count: Int) throws -> [Card] {
        precondition(count > 0 && count <= Limits.maxNodesPerCanvas, "Card count \(count)")
        let device = DeviceID(rawValue: UUID())
        let canvas = CanvasID(rawValue: UUID())
        let meta = RecordMeta(created: HybridTimestamp(wallMillis: 1, counter: 0, device: device))
        let key = try FractionalIndex(rawValue: "V")
        let rows = (count + 99) / 100
        return try (0..<count).map { index in
            try Card(
                id: CardID(rawValue: UUID()),
                meta: meta,
                canvasID: canvas,
                frame: Rect(
                    origin: Point(
                        x: Double(index % 100) * 120 - 6_000,
                        y: Double(index / 100) * 90 - Double(rows) * 45
                    ),
                    size: Size(width: 100, height: 70)
                ),
                title: "Card \(index)",
                sortKey: key
            )
        }
    }
}
