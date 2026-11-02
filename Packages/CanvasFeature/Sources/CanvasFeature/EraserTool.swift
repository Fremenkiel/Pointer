import Geometry
import InkEngine

/// The eraser: a circle of one of three sizes on the screen (architecture.md 4.4, D-06, D-201).
enum EraserTool {
    /// The capacity of the sample list: the longest gesture, so that no sample grows it (M-07).
    static let sampleCapacity = EraserPath.maxSamples

    /// Returns the eraser radius in canvas units for a radius of `viewPoints` on the screen at a
    /// zoom.
    ///
    /// - Precondition: `viewPoints` and `zoom` are positive.
    static func canvasRadius(viewPoints: Double, zoom: Double) -> Double {
        precondition(viewPoints > 0, "Eraser radius must be positive, got \(viewPoints)")
        precondition(zoom > 0 && zoom.isFinite, "Zoom must be positive, got \(zoom)")
        return viewPoints / zoom
    }
}
