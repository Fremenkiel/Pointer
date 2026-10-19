import DesignSystem
import SwiftUI

/// One square icon button of the chrome on top of the canvas.
struct ChromeIcon: View {
    let icon: String
    var isEnabled = true
    var isSelected = false

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
