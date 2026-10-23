import DesignSystem
import SwiftUI

/// The undo, redo, and export buttons in the top right corner (UNDO-01, EXP-01). Undo and redo
/// are off while their list is empty. Export is off while an export runs.
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
            button(
                DesignSystem.Icon.export,
                label: CanvasStrings.export,
                isEnabled: !controls.isExporting
            ) {
                controls.export()
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
