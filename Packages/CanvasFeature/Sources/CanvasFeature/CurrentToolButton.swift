import SwiftUI

/// The button in the top left corner that shows the current tool. A finger tap opens the tool
/// palette under it (TOOL-07, D-64).
struct CurrentToolButton: View {
    let controls: ToolControls

    var body: some View {
        Button(action: controls.openPalette) {
            ChromeIcon(icon: controls.selected.icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CanvasStrings.tools)
        .accessibilityValue(controls.selected.label)
    }
}
