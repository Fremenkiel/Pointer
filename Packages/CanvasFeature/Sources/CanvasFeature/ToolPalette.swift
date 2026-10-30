import DesignSystem
import SwiftUI

/// The tool palette: pen, eraser, text, undo, and redo (PEN-03, D-63, D-87). While the pen is
/// the selected tool, a second row holds the pen widths (TOOL-09, D-199). A tap on a tool or on
/// a width picks it and closes the palette. Undo and redo keep it open.
struct ToolPalette: View {
    /// The state of the tools.
    let tools: ToolControls
    /// The state of the undo and redo buttons.
    let history: HistoryControls

    /// The tools and the undo and redo buttons in a row, and the pen widths below them.
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            toolRow
            if tools.selected == .pen {
                widths
            }
        }
        .padding(DesignSystem.Spacing.small)
    }

    /// The tools and the undo and redo buttons.
    private var toolRow: some View {
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
            HistoryButtons(controls: history, showsCanvasCommands: false)
        }
    }

    /// The pen widths in a row. Only the pen has a width (TOOL-09).
    private var widths: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            ForEach(PenWidth.allCases, id: \.self) { width in
                Button {
                    tools.selectWidth(width)
                } label: {
                    PenWidthIcon(width: width, isSelected: width == tools.penWidth)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(width.label)
                .accessibilityAddTraits(width == tools.penWidth ? .isSelected : [])
                .accessibilityIdentifier("penWidth.\(width)")
                .largeContent(width.label, icon: DesignSystem.Icon.pen)
            }
        }
    }
}
