import SwiftUI
import Testing

@testable import CanvasFeature

/// The up button of the chrome inside a card (CARD-04, TEST-07). `ViewSnapshot` comes from the
/// selector snapshots, which `PointerDeviceTests` compiles in the same target.
@MainActor
@Suite("Up button snapshots")
struct UpButtonSnapshotTests {
    @Test("The up button shows its icon in the style of the chrome")
    func upButton() throws {
        try ViewSnapshot.assertMatches(UpButton {}, named: "up-button")
    }
}
