import SwiftUI
import Testing

@testable import CanvasFeature

/// The tool palette and the current-tool button for each tool (TOOL-07, TEST-07).
@MainActor
@Suite("Tool control snapshots")
struct ToolControlsSnapshotTests {
    private func tools(_ tool: Tool) -> ToolControls {
        let controls = ToolControls()
        controls.selected = tool
        return controls
    }

    @Test("The palette marks the current tool", arguments: Tool.allCases)
    func palette(tool: Tool) throws {
        let history = HistoryControls()
        history.canUndo = true
        try ViewSnapshot.assertMatches(
            ToolPalette(tools: tools(tool), history: history),
            named: "tool-palette-\(tool)"
        )
    }

    @Test("The button shows the current tool", arguments: Tool.allCases)
    func button(tool: Tool) throws {
        try ViewSnapshot.assertMatches(
            CurrentToolButton(controls: tools(tool)),
            named: "tool-button-\(tool)"
        )
    }
}
