import DesignSystem
import SwiftUI

/// The icon of one eraser size in the palette: an outline circle with the radius of the eraser
/// on the screen, so that the icon shows the ring of the hover dot (TOOL-04, D-133, D-201). It
/// sits on the square background of the chrome.
struct EraserSizeIcon: View {
    /// The size that the circle shows.
    let size: EraserSize
    /// `true` shows the circle on the selection background.
    var isSelected = false

    /// The circle on its square background.
    var body: some View {
        let diameter = CGFloat(size.viewPoints) * 2
        Circle()
            .strokeBorder(
                DesignSystem.Color.chromeForeground,
                lineWidth: DesignSystem.Size.hoverRingWidth
            )
            .frame(width: diameter, height: diameter)
            .frame(width: DesignSystem.Size.tapTarget, height: DesignSystem.Size.tapTarget)
            .background(
                isSelected
                    ? DesignSystem.Color.chromeSelection : DesignSystem.Color.chromeBackground,
                in: RoundedRectangle(cornerRadius: DesignSystem.Size.cornerRadius)
            )
    }
}
