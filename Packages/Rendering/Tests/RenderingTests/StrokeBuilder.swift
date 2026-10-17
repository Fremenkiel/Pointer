import Foundation
import Geometry
import Model

/// Makes strokes for the renderer tests.
enum StrokeBuilder {
    static let canvas = CanvasID(
        rawValue: UUID(uuid: (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )
    static let device = DeviceID(
        rawValue: UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )

    /// Makes one stroke through canvas points, with a fresh ID.
    static func stroke(_ points: [Point], width: Float = 2, seed: UInt8 = 0) -> Stroke {
        let origin = points[0]
        let ink = points.map { point in
            InkPoint(x: Float(point.x - origin.x), y: Float(point.y - origin.y), force: 1, time: 0)
        }
        var bytes: [UInt8] = Array(repeating: 0, count: 16)
        bytes[0] = seed
        bytes[1] = UInt8(truncatingIfNeeded: points.count)
        bytes[2] = UInt8(truncatingIfNeeded: Int(origin.x))
        bytes[3] = UInt8(truncatingIfNeeded: Int(origin.y))
        let uuid = UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], 0, 0, 0x70, 0, 0x80, 0, 0, 0, 0, 0, 0, 0
            )
        )
        return Stroke(
            id: StrokeID(rawValue: uuid),
            canvasID: canvas,
            created: HybridTimestamp(wallMillis: 0, counter: 0, device: device),
            origin: origin,
            width: width,
            points: InkPoints(ink)
        )
    }

    /// A tight zigzag: 40 points that turn by almost 180 degrees at each point (review A-06).
    static func zigzag(at origin: Point) -> Stroke {
        let points = (0..<40).map { index in
            Point(
                x: origin.x + Double(index) * 1.5,
                y: origin.y + (index.isMultiple(of: 2) ? 0 : 12)
            )
        }
        return stroke(points)
    }

    /// A gentle curve of 30 points.
    static func curve(at origin: Point, seed: UInt8 = 0) -> Stroke {
        let points = (0..<30).map { index in
            let t = Double(index) / 29
            return Point(x: origin.x + t * 120, y: origin.y + sin(t * .pi * 2) * 30)
        }
        return stroke(points, seed: seed)
    }
}
