import DesignSystem
import SwiftUI

/// The icon of one pen width in the palette: a dot with the width of the pen, scaled for the
/// screen, on the square background of the chrome (TOOL-09, D-199).
struct PenWidthIcon: View {
    /// The width that the dot shows.
    let width: PenWidth
    /// `true` shows the dot on the selection background.
    var isSelected = false

    /// The dot on its square background.
    var body: some View {
        let diameter = CGFloat(width.canvasPoints) * DesignSystem.Size.penWidthDotScale
        Circle()
            .fill(DesignSystem.Color.chromeForeground)
            .frame(width: diameter, height: diameter)
            .frame(width: DesignSystem.Size.tapTarget, height: DesignSystem.Size.tapTarget)
            .background(
                isSelected
                    ? DesignSystem.Color.chromeSelection : DesignSystem.Color.chromeBackground,
                in: RoundedRectangle(cornerRadius: DesignSystem.Size.cornerRadius)
            )
    }
}
