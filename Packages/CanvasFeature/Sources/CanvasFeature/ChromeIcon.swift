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
            .font(DesignSystem.Font.chromeTitle)
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
