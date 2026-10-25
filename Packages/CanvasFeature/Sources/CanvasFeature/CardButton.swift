import DesignSystem
import SwiftUI

/// The button of the chrome that shows a new card at the left edge of the screen (CARD-01,
/// D-117).
struct CardButton: View {
    /// Shows a new card.
    let action: () -> Void

    /// The button.
    var body: some View {
        Button(action: action) {
            ChromeIcon(icon: DesignSystem.Icon.card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CanvasStrings.newCard)
        .accessibilityIdentifier("newCard")
        .largeContent(CanvasStrings.newCard, icon: DesignSystem.Icon.card)
    }
}

/// The current-tool button and the card button right of it (D-64, D-117).
struct ToolChrome: View {
    /// The state of the current-tool button and the card button.
    let controls: ToolControls

    /// The two buttons side by side.
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            CurrentToolButton(controls: controls)
            CardButton(action: controls.newCard)
        }
    }
}
