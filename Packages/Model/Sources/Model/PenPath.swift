import Geometry

/// A pen path that the input system finished, in its source space (architecture.md 4.2).
public struct PenPath: Sendable {
    /// The control points in the source space.
    public let samples: [ControlPointSample]
    /// The transform from the source space to canvas space.
    public let toCanvas: Transform
    /// The line width in the units of the source space.
    public let width: Double

    /// Makes a path.
    public init(samples: [ControlPointSample], toCanvas: Transform, width: Double) {
        self.samples = samples
        self.toCanvas = toCanvas
        self.width = width
    }
}
