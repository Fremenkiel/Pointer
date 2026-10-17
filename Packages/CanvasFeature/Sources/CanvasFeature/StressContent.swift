import Foundation
import Geometry
import Model

/// Makes many synthetic strokes for the device performance tests of M2 (acceptance 2 and 10).
///
/// The strokes lie in a grid around the canvas origin. At zoom 0.25 on a 13-inch iPad, a canvas
/// of 20,000 strokes fills the screen.
public enum StressContent {
    /// The distance between the starts of two strokes, in canvas points.
    static let spacing = 28.0
    /// The strokes per grid row.
    static let columns = 200

    /// Returns `count` wavy strokes of `pointsPerStroke` control points each.
    ///
    /// - Precondition: `count` is within the stroke limit, and each stroke has 2 points at least.
    public static func makeStrokes(
        count: Int,
        pointsPerStroke: Int,
        canvasID: CanvasID,
        factory: inout StrokeFactory
    ) -> [Stroke] {
        precondition(
            count >= 0 && count <= Limits.maxStrokesPerCanvas,
            "Stroke count \(count) out of range"
        )
        precondition(pointsPerStroke >= 2, "A stroke needs 2 points, got \(pointsPerStroke)")
        let rows = (count + columns - 1) / columns
        let origin = Point(x: -Double(columns) * spacing / 2, y: -Double(rows) * spacing / 2)
        var strokes: [Stroke] = []
        strokes.reserveCapacity(count)
        for index in 0..<count {
            let start =
                origin
                + Vector(
                    dx: Double(index % columns) * spacing,
                    dy: Double(index / columns) * spacing
                )
            let samples = (0..<pointsPerStroke).map { step in
                let t = Double(step) / Double(pointsPerStroke - 1)
                let location =
                    start + Vector(dx: t * spacing * 0.8, dy: sin(t * .pi * 4) * spacing * 0.3)
                return ControlPointSample(location: location, force: 1, timeOffset: t)
            }
            let path = PenPath(samples: samples, toCanvas: .identity, width: 2)
            if let made = try? factory.makeStrokes(from: path, canvasID: canvasID) {
                strokes.append(contentsOf: made)
            }
        }
        return strokes
    }
}
