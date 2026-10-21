import Geometry

/// The content bounds and the open camera of a canvas (architecture.md 6.2, CARD-03).
extension CanvasContent {
    /// The bounds of the live content: the bounds of the strokes, the frames of the cards, and
    /// the origins of the text boxes. `Model` has no text layout, so a text box counts by its
    /// top-left corner. `nil` for an empty canvas.
    public var contentBounds: Rect? {
        var low = Point(x: Double.infinity, y: Double.infinity)
        var high = Point(x: -Double.infinity, y: -Double.infinity)
        func include(_ rect: Rect) {
            low = Point(x: min(low.x, rect.minX), y: min(low.y, rect.minY))
            high = Point(x: max(high.x, rect.maxX), y: max(high.y, rect.maxY))
        }
        for stroke in strokes.values { include(stroke.bounds) }
        for card in cards.values { include(card.frame) }
        for box in textBoxes.values { include(Rect(origin: box.origin, size: .zero)) }
        guard low.x <= high.x, low.y <= high.y else { return nil }
        let bounds = Rect(minX: low.x, minY: low.y, maxX: high.x, maxY: high.y)
        assert(bounds.origin.isFinite, "Live content has finite bounds")
        return bounds
    }

    /// The camera of an open by a double tap: the standard zoom, centered on the content bounds,
    /// or on the origin for an empty canvas (CARD-03, D-99).
    public var openCamera: Camera {
        Camera(center: contentBounds?.center ?? .zero, zoom: Limits.standardZoom)
    }
}
