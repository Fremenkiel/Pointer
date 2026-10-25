import SwiftUI
import Testing

@testable import CanvasFeature

/// The icon buttons at the largest text size, AX5: they keep the size of the standard text size
/// and show the Large Content Viewer instead (D-179, TEST-07).
@MainActor
@Suite("Chrome snapshots at the largest text size")
struct LargeTextChromeSnapshotTests {
    @Test("The tool button and the card button keep their size")
    func toolChrome() throws {
        let controls = ToolControls()
        controls.selected = .pen
        try ViewSnapshot.assertMatches(
            ToolChrome(controls: controls).environment(\.dynamicTypeSize, .accessibility5),
            named: "tool-chrome"
        )
    }

    @Test("Undo, redo, and export keep their size")
    func historyButtons() throws {
        let controls = HistoryControls()
        controls.canUndo = true
        controls.canRedo = true
        try ViewSnapshot.assertMatches(
            HistoryButtons(controls: controls).environment(\.dynamicTypeSize, .accessibility5),
            named: "history-buttons-on"
        )
    }

    @Test("The up button keeps its size")
    func upButton() throws {
        try ViewSnapshot.assertMatches(
            UpButton {}.environment(\.dynamicTypeSize, .accessibility5),
            named: "up-button"
        )
    }
}
