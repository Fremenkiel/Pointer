import Foundation
import Geometry
import Model

/// Makes canvas content for the Export tests.
enum ExportContent {
    /// The canvas of all test content.
    static let canvas = CanvasID(
        rawValue: UUID(uuid: (8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )
    private static let device = DeviceID(
        rawValue: UUID(uuid: (9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )
    private static let time = HybridTimestamp(wallMillis: 1, counter: 0, device: device)

    /// Makes a stroke through canvas points, with the offsets from the first point.
    ///
    /// - Precondition: At least 2 points.
    static func stroke(_ points: [Point], width: Float = 2) -> Stroke {
        precondition(points.count >= 2, "A stroke needs 2 points, got \(points.count)")
        let origin = points[0]
        let ink = points.map { point in
            InkPoint(x: Float(point.x - origin.x), y: Float(point.y - origin.y), force: 1, time: 0)
        }
        return Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: canvas,
            created: time,
            origin: origin,
            width: width,
            points: InkPoints(ink)
        )
    }

    /// Makes a wavy stroke of `count` points that starts at `origin`.
    static func wave(count: Int, at origin: Point, width: Float = 2) -> Stroke {
        let points = (0..<count).map { index in
            Point(
                x: origin.x + Double(index) * 3,
                y: origin.y + (index.isMultiple(of: 2) ? 0 : 10) + Double(index % 7)
            )
        }
        return stroke(points, width: width)
    }

    /// Makes a text box.
    static func textBox(_ text: String, at origin: Point) throws -> TextBox {
        try TextBox(
            id: TextBoxID(rawValue: UUID()),
            meta: RecordMeta(created: time),
            canvasID: canvas,
            origin: origin,
            text: text,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    /// Makes a card.
    static func card(title: String?, frame: Rect) throws -> Card {
        try Card(
            id: CardID(rawValue: UUID()),
            meta: RecordMeta(created: time),
            canvasID: canvas,
            frame: frame,
            title: title,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    /// Makes the content of one canvas.
    static func content(
        strokes: [Stroke] = [],
        textBoxes: [TextBox] = [],
        cards: [Card] = []
    ) throws -> CanvasContent {
        var content = CanvasContent(canvasID: canvas)
        for stroke in strokes { try content.add(stroke, limit: Limits.maxStrokesAfterErase) }
        for box in textBoxes { try content.add(box) }
        for card in cards { try content.add(card) }
        return content
    }
}
