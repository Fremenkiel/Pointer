import Geometry

/// One control point of a pen path as the input system gives it, before the conversion.
public struct ControlPointSample: Sendable {
    /// The position in the source space, for example view space.
    public let location: Point
    /// The pencil force from 0 to 1, or -1 if the pencil has no pressure.
    public let force: Double
    /// Seconds since the start of the path.
    public let timeOffset: Double

    /// Makes a sample.
    public init(location: Point, force: Double, timeOffset: Double) {
        self.location = location
        self.force = force
        self.timeOffset = timeOffset
    }
}
