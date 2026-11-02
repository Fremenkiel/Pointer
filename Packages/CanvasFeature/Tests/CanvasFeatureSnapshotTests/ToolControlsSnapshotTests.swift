import SwiftUI
import Testing

@testable import CanvasFeature

/// The tool palette, the current-tool button for each tool, and the card button (TOOL-07,
/// D-117, D-201, TEST-07).
@MainActor
@Suite("Tool control snapshots")
struct ToolControlsSnapshotTests {
    private func tools(_ tool: Tool) -> ToolControls {
        let controls = ToolControls()
        controls.selected = tool
        return controls
    }

    @Test(
        "The palette shows the tools, the sizes of the selected tool, and undo and redo in one row",
        arguments: Tool.allCases
    )
    func palette(tool: Tool) throws {
        let history = HistoryControls()
        history.canUndo = true
        try ViewSnapshot.assertMatches(
            ToolPalette(tools: tools(tool), history: history),
            named: "tool-palette-\(tool)"
        )
    }

    @Test("The palette marks the picked pen width")
    func paletteThickPen() throws {
        let controls = tools(.pen)
        controls.penWidth = .thick
        let history = HistoryControls()
        history.canUndo = true
        try ViewSnapshot.assertMatches(
            ToolPalette(tools: controls, history: history),
            named: "tool-palette-pen-thick"
        )
    }

    @Test("The palette marks the picked eraser size (D-201)")
    func paletteLargeEraser() throws {
        let controls = tools(.eraser)
        controls.eraserSize = .large
        let history = HistoryControls()
        history.canUndo = true
        try ViewSnapshot.assertMatches(
            ToolPalette(tools: controls, history: history),
            named: "tool-palette-eraser-large"
        )
    }

    @Test("The button shows the current tool", arguments: Tool.allCases)
    func button(tool: Tool) throws {
        try ViewSnapshot.assertMatches(
            CurrentToolButton(controls: tools(tool)),
            named: "tool-button-\(tool)"
        )
    }

    @Test("The chrome shows the card button right of the tool button (D-117)")
    func chrome() throws {
        try ViewSnapshot.assertMatches(ToolChrome(controls: tools(.pen)), named: "tool-chrome")
    }
}
