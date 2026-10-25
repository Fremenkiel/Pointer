import SwiftUI

/// The button in the top left corner that shows the current tool. A finger tap opens the tool
/// palette under it (TOOL-07, D-64).
struct CurrentToolButton: View {
    /// The state of the button and the palette.
    let controls: ToolControls

    /// The button.
    var body: some View {
        Button(action: controls.openPalette) {
            ChromeIcon(icon: controls.selected.icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CanvasStrings.tools)
        .accessibilityValue(controls.selected.label)
        .accessibilityIdentifier("tools")
        .largeContent(controls.selected.label, icon: controls.selected.icon)
    }
}
