import DesignSystem
import SwiftUI

/// The button of the chrome that leaves the current card for its parent canvas (CARD-04). It
/// shows only inside a card (architecture.md 6.4).
public struct UpButton: View {
    private let action: () -> Void

    /// Makes the button.
    public init(action: @escaping () -> Void) {
        self.action = action
    }

    /// The button.
    public var body: some View {
        Button(action: action) {
            ChromeIcon(icon: DesignSystem.Icon.up)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CanvasStrings.up)
    }
}
