import UIKit

/// The tool change of a double tap on the pencil (architecture.md 4.5, PEN-01, PEN-02, D-130).
enum ToolSwitch {
    /// Returns the tool after a double tap, or `nil` if the double tap does nothing.
    ///
    /// Only the settings "Switch to eraser" and "Switch to previous tool" switch the tool: the pen
    /// goes to the eraser, and the eraser and the text tool go to the pen. Every other setting,
    /// also a value of a later SDK, does nothing (D-130).
    static func tool(after selected: Tool, action: UIPencilPreferredAction) -> Tool? {
        switch action {
        case .switchEraser, .switchPrevious:
            return selected == .pen ? .eraser : .pen
        case .ignore, .showColorPalette, .showInkAttributes, .showContextualPalette,
            .runSystemShortcut:
            return nil
        @unknown default:
            return nil
        }
    }
}
