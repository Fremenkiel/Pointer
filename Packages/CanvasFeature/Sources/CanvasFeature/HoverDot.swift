import DesignSystem
import UIKit

/// The mark that shows where the hovering pencil will touch (architecture.md 4.6, PEN-04,
/// D-128, D-133).
struct HoverDot: Equatable {
    /// The center of the mark in view points: the hover location.
    let center: CGPoint
    /// The radius of the mark in view points.
    let radius: CGFloat
    /// `true` for the outline circle of the eraser, `false` for the filled dot of the pen and the
    /// text tool.
    let isRing: Bool

    /// Returns the mark of a hover sample, or `nil` if no mark shows.
    ///
    /// The pen and the text tool show a small dot. The eraser shows an outline circle with the
    /// radius of `eraserSize` (D-201). No mark shows while the user turned "Show Hover Preview"
    /// off, or while `isBlocked`: the pencil touches the screen, or a card flight runs.
    static func mark(
        tool: Tool,
        eraserSize: EraserSize,
        isPreviewOn: Bool,
        location: CGPoint,
        isBlocked: Bool
    ) -> HoverDot? {
        guard isPreviewOn, !isBlocked else { return nil }
        switch tool {
        case .pen, .text:
            return HoverDot(
                center: location,
                radius: DesignSystem.Size.hoverDotRadius,
                isRing: false
            )
        case .eraser:
            return HoverDot(center: location, radius: eraserSize.viewPoints, isRing: true)
        }
    }
}
