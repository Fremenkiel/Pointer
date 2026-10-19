import Geometry

/// The eraser: a circle of a fixed size on the screen (architecture.md 4.4, D-06).
enum EraserTool {
    /// The eraser radius in view points. It stays the same on the screen at every zoom.
    static let radius = 8.0
    /// The first capacity of the sample list of a gesture: 4 s at 240 Hz.
    static let sampleCapacity = 1_024

    /// Returns the eraser radius in canvas units at a zoom.
    ///
    /// - Precondition: `zoom` is positive.
    static func canvasRadius(zoom: Double) -> Double {
        precondition(zoom > 0 && zoom.isFinite, "Zoom must be positive, got \(zoom)")
        return radius / zoom
    }
}
