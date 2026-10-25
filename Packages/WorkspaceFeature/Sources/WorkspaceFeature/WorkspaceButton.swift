import DesignSystem
import SwiftUI

/// The button in the top left corner with the name of the current workspace (WS-01).
struct WorkspaceButton: View {
    /// The name of the current workspace.
    let title: String
    /// Opens the selector.
    let action: () -> Void

    /// The name and the expand icon.
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.small) {
                Text(verbatim: title)
                    .font(DesignSystem.Font.chromeBar)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: DesignSystem.Size.selectorTitleWidth, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: DesignSystem.Icon.expand)
                    .font(DesignSystem.Font.chromeBarDetail)
            }
            .foregroundStyle(DesignSystem.Color.chromeForeground)
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .frame(minHeight: DesignSystem.Size.tapTarget)
            .background(
                DesignSystem.Color.chromeBackground,
                in: RoundedRectangle(cornerRadius: DesignSystem.Size.cornerRadius)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WorkspaceStrings.selectorLabel)
        .accessibilityValue(title)
        .accessibilityIdentifier("workspaces")
        // The title keeps its size in the bar, so the viewer shows it large (D-179).
        .accessibilityShowsLargeContentViewer {
            Label(title, systemImage: DesignSystem.Icon.expand)
        }
    }
}
