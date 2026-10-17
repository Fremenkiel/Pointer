/// One control point of a stroke, 16 bytes, with the layout of the point BLOB (storage.md 3.4).
public struct InkPoint: Hashable, Sendable {
    /// The x offset from the stroke origin, in canvas points.
    public let x: Float
    /// The y offset from the stroke origin, in canvas points.
    public let y: Float
    /// The pencil force from 0 to 1, or -1 if the pencil has no pressure.
    public let force: Float
    /// Seconds since the first point of the stroke.
    public let time: Float

    /// Makes a point.
    public init(x: Float, y: Float, force: Float, time: Float) {
        self.x = x
        self.y = y
        self.force = force
        self.time = time
    }
}
