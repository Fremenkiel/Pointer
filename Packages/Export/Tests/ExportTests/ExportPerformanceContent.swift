import Foundation
import Geometry
import Model

/// The large canvases of `ExportPerformanceTests`, on the canvas of `ExportContent`.
extension ExportPerformanceTests {
    /// The strokes of D-56: 20,000 strokes of 300 points on a grid of 40 points, as
    /// `D56Library` stores them.
    static func d56Strokes() -> [Stroke] {
        let path = (0..<300).map { Point(x: Double($0) / 10, y: Double($0 % 7)) }
        return (0..<20_000).map { index in
            let origin = Point(
                x: Double(index % 200) * 40 - 4_000,
                y: Double(index / 200) * 40 - 2_000
            )
            return ExportContent.stroke(path.map { origin + ($0 - .zero) })
        }
    }

    /// Text boxes of 200 characters on a grid of 120 by 90 points, as `D56Library` stores them.
    static func textBoxes(count: Int) throws -> [TextBox] {
        let text = String(repeating: "node ", count: 40)
        return try (0..<count).map { index in
            try ExportContent.textBox(
                text,
                at: Point(x: Double(index % 100) * 120, y: Double(index / 100) * 90 + 5_000)
            )
        }
    }

    /// Cards of 100 by 70 points with the titles "Card N", as `D56Library` stores them.
    static func cards(count: Int) throws -> [Card] {
        try (0..<count).map { index in
            try ExportContent.card(
                title: "Card \(index)",
                frame: Rect(
                    origin: Point(x: Double(index % 100) * 120, y: Double(index / 100) * 90),
                    size: Size(width: 100, height: 70)
                )
            )
        }
    }

    /// The handwriting strokes of `FrameLoopTests`: 60 points about 2 points apart, 120 points
    /// long, in rows of 100.
    static func handwriting(count: Int) -> [Stroke] {
        (0..<count).map { index in
            let origin = Point(
                x: Double(index % 100) * 140 - 7_000,
                y: Double(index / 100) * 40 - 4_000
            )
            let path = (0..<60).map { step in
                let t = Double(step)
                return Point(x: origin.x + t * 2, y: origin.y + sin(t * 0.7 + Double(index)) * 9)
            }
            return ExportContent.stroke(path)
        }
    }
}
