import PencilKit
import UIKit

/// The pen: white monoline ink with a fixed width (TOOL-02, D-05, D-37).
enum PenTool {
    /// The pen width in canvas points. A start value. Tune it on a device (D-37).
    static let width = 2.0

    /// Returns the live tool for a camera zoom. The live `PKCanvasView` draws at zoom 1 in view
    /// space, so the tool width is the pen width times the zoom (architecture.md 4.2).
    ///
    /// The color is `UIColor.white` and the canvas view uses the light interface style, so
    /// PencilKit does not convert the color (D-38).
    ///
    /// - Precondition: `zoom` is positive.
    static func inkingTool(zoom: Double) -> PKInkingTool {
        precondition(zoom > 0 && zoom.isFinite, "Zoom must be positive, got \(zoom)")
        return PKInkingTool(.monoline, color: .white, width: width * zoom)
    }
}
