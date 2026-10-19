import UIKit

/// Where a squeeze opens the tool palette (architecture.md 4.5, D-63).
enum PaletteAnchor {
    /// Returns the point of the palette for a squeeze, or `nil` if the squeeze opens nothing.
    ///
    /// Only the end of a squeeze acts. The setting "Ignore" opens nothing, and the app never
    /// gets "Run Shortcut". Every other setting opens the palette at the pencil tip, or at the
    /// last pencil location if the squeeze has no hover pose.
    static func squeeze(
        isEnded: Bool,
        action: UIPencilPreferredAction,
        hoverLocation: CGPoint?,
        lastPencilLocation: CGPoint?
    ) -> CGPoint? {
        guard isEnded else { return nil }
        switch action {
        case .ignore, .runSystemShortcut:
            return nil
        default:
            return hoverLocation ?? lastPencilLocation
        }
    }
}
