import Geometry
import InkEngine

/// The eraser: a circle of a fixed size on the screen (architecture.md 4.4, D-06).
enum EraserTool {
    /// The eraser radius in view points. It stays the same on the screen at every zoom.
    static let radius = 8.0
    /// The capacity of the sample list: the longest gesture, so that no sample grows it (M-07).
    static let sampleCapacity = EraserPath.maxSamples

    /// Returns the eraser radius in canvas units at a zoom.
    ///
    /// - Precondition: `zoom` is positive.
    static func canvasRadius(zoom: Double) -> Double {
        precondition(zoom > 0 && zoom.isFinite, "Zoom must be positive, got \(zoom)")
        return radius / zoom
    }
}
