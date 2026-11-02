import DesignSystem
import SwiftUI

/// The tool palette in one row: pen, eraser, text, the sizes of the selected tool, and undo and
/// redo (PEN-03, D-63, D-87, D-201). The pen has three widths (TOOL-09, D-199) and the eraser has
/// three sizes (TOOL-04). The text tool has no size. A tap on a tool keeps the palette open, and
/// the row shows the sizes of that tool. A tap on a size closes the palette. Undo and redo keep
/// it open.
struct ToolPalette: View {
    /// The state of the tools.
    let tools: ToolControls
    /// The state of the undo and redo buttons.
    let history: HistoryControls

    /// The tools, the sizes of the selected tool, and the undo and redo buttons in a row. A
    /// group starts after a gap of `Spacing.medium`: the small spacing of the row plus the
    /// small leading padding of the group.
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            toolButtons
            if tools.selected == .pen {
                penWidths.padding(.leading, DesignSystem.Spacing.small)
            }
            if tools.selected == .eraser {
                eraserSizes.padding(.leading, DesignSystem.Spacing.small)
            }
            HistoryButtons(controls: history, showsCanvasCommands: false)
                .padding(.leading, DesignSystem.Spacing.small)
        }
        .padding(DesignSystem.Spacing.small)
        .animation(.default, value: tools.selected)
    }

    /// The three tools.
    private var toolButtons: some View {
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
    }

    /// The pen widths, shown while the pen is the selected tool (TOOL-09).
    private var penWidths: some View {
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

    /// The eraser sizes, shown while the eraser is the selected tool (TOOL-04).
    private var eraserSizes: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            ForEach(EraserSize.allCases, id: \.self) { size in
                Button {
                    tools.selectEraserSize(size)
                } label: {
                    EraserSizeIcon(size: size, isSelected: size == tools.eraserSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(size.label)
                .accessibilityAddTraits(size == tools.eraserSize ? .isSelected : [])
                .accessibilityIdentifier("eraserSize.\(size)")
                .largeContent(size.label, icon: DesignSystem.Icon.eraser)
            }
        }
    }
}
