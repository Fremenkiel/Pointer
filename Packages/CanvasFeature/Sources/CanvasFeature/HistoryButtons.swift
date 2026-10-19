import DesignSystem
import SwiftUI

/// The undo and redo buttons in the top right corner (UNDO-01). A button is off while its list
/// is empty.
struct HistoryButtons: View {
    let controls: HistoryControls

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            button(DesignSystem.Icon.undo, label: CanvasStrings.undo, isEnabled: controls.canUndo) {
                controls.undo()
            }
            button(DesignSystem.Icon.redo, label: CanvasStrings.redo, isEnabled: controls.canRedo) {
                controls.redo()
            }
        }
    }

    private func button(
        _ icon: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ChromeIcon(icon: icon, isEnabled: isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}
