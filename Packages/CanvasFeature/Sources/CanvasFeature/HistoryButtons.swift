import DesignSystem
import SwiftUI

/// The undo, redo, and export buttons in the top right corner (UNDO-01, EXP-01). Undo and redo
/// are off while their list is empty. Export is off while an export runs.
struct HistoryButtons: View {
    /// The state of the buttons.
    let controls: HistoryControls
    /// `false` in the tool palette, which shows undo and redo only (D-63).
    var showsExport = true

    /// The buttons in a row.
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            button(
                DesignSystem.Icon.undo,
                label: CanvasStrings.undo,
                identifier: "undo",
                isEnabled: controls.canUndo
            ) {
                controls.undo()
            }
            button(
                DesignSystem.Icon.redo,
                label: CanvasStrings.redo,
                identifier: "redo",
                isEnabled: controls.canRedo
            ) {
                controls.redo()
            }
            if showsExport {
                button(
                    DesignSystem.Icon.export,
                    label: CanvasStrings.export,
                    identifier: "export",
                    isEnabled: !controls.isExporting
                ) {
                    controls.export()
                }
            }
        }
    }

    private func button(
        _ icon: String,
        label: String,
        identifier: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ChromeIcon(icon: icon, isEnabled: isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .largeContent(label, icon: icon)
    }
}
