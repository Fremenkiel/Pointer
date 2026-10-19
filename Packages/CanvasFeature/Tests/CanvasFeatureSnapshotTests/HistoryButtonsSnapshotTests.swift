import SwiftUI
import Testing

@testable import CanvasFeature

/// The undo and redo buttons (UNDO-01, TEST-07). `ViewSnapshot` comes from the selector
/// snapshots, which `PointerDeviceTests` compiles in the same target.
@MainActor
@Suite(
    "History button snapshots",
    .enabled(
        if: ViewSnapshot.canReadReferences,
        "The references are on the Mac, so only the simulator reads them"
    )
)
struct HistoryButtonsSnapshotTests {
    private func controls(canUndo: Bool, canRedo: Bool) -> HistoryControls {
        let controls = HistoryControls()
        controls.canUndo = canUndo
        controls.canRedo = canRedo
        return controls
    }

    @Test("Both buttons are on")
    func bothOn() throws {
        try ViewSnapshot.assertMatches(
            HistoryButtons(controls: controls(canUndo: true, canRedo: true)),
            named: "history-buttons-on"
        )
    }

    @Test("Both buttons are off while the lists are empty")
    func bothOff() throws {
        try ViewSnapshot.assertMatches(
            HistoryButtons(controls: controls(canUndo: false, canRedo: false)),
            named: "history-buttons-off"
        )
    }

    @Test("Undo is on and redo is off after a new step")
    func undoOnly() throws {
        try ViewSnapshot.assertMatches(
            HistoryButtons(controls: controls(canUndo: true, canRedo: false)),
            named: "history-buttons-undo"
        )
    }
}
