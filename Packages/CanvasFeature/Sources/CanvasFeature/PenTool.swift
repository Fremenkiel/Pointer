import DesignSystem
import PencilKit
import UIKit

/// The pen: white monoline ink with the width that the user picked (TOOL-02, TOOL-09, D-05,
/// D-37, D-199). Pressure does not change the width.
enum PenTool {
    /// Returns the live tool for a pen width and a camera zoom. The live `PKCanvasView` draws at
    /// zoom 1 in view space, so the tool width is the pen width times the zoom (architecture.md
    /// 4.2).
    ///
    /// The color is the ink token, white, and the canvas view uses the light interface style,
    /// so PencilKit does not convert the color (D-38).
    ///
    /// - Precondition: `zoom` is positive.
    static func inkingTool(width: PenWidth, zoom: Double) -> PKInkingTool {
        precondition(zoom > 0 && zoom.isFinite, "Zoom must be positive, got \(zoom)")
        return PKInkingTool(
            .monoline,
            color: DesignSystem.Color.ink,
            width: width.canvasPoints * zoom
        )
    }
}
