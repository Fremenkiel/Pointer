import DesignSystem
import SwiftUI

/// One square icon button of the chrome on top of the canvas.
struct ChromeIcon: View {
    /// The name of the SF Symbol.
    let icon: String
    /// `false` shows the icon in the disabled color.
    var isEnabled = true
    /// `true` shows the icon on the selection background.
    var isSelected = false

    /// The icon on its square background.
    var body: some View {
        Image(systemName: icon)
            .font(DesignSystem.Font.chromeBar)
            .foregroundStyle(
                isEnabled ? DesignSystem.Color.chromeForeground : DesignSystem.Color.chromeDisabled
            )
            .frame(width: DesignSystem.Size.tapTarget, height: DesignSystem.Size.tapTarget)
            .background(
                isSelected
                    ? DesignSystem.Color.chromeSelection : DesignSystem.Color.chromeBackground,
                in: RoundedRectangle(cornerRadius: DesignSystem.Size.cornerRadius)
            )
    }
}

extension View {
    /// Shows the icon and the label of a button of the bar in the Large Content Viewer, because
    /// the icon keeps its size at large text sizes (D-179).
    func largeContent(_ label: String, icon: String) -> some View {
        accessibilityShowsLargeContentViewer {
            Label(label, systemImage: icon)
        }
    }
}
