import DesignSystem
import SwiftUI

/// The tool palette: pen, eraser, undo, and redo (PEN-03, D-63). The text tool joins it in M5.
/// A tap on a tool picks it and closes the palette. Undo and redo keep it open.
struct ToolPalette: View {
    /// The state of the tools.
    let tools: ToolControls
    /// The state of the undo and redo buttons.
    let history: HistoryControls

    /// The tools and the undo and redo buttons in a row.
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            ForEach(Tool.allCases, id: \.self) { tool in
                Button {
                    tools.select(tool)
                } label: {
                    ChromeIcon(icon: tool.icon, isSelected: tool == tools.selected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.label)
                .accessibilityAddTraits(tool == tools.selected ? .isSelected : [])
                .largeContent(tool.label, icon: tool.icon)
            }
            HistoryButtons(controls: history, showsExport: false)
        }
        .padding(DesignSystem.Spacing.small)
    }
}
