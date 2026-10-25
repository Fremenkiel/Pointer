import DesignSystem
import Model
import SwiftUI

/// The list of all workspaces with the commands to switch, create, rename, and delete (WS-02,
/// WS-03).
struct WorkspaceList: View {
    /// The workspaces in the order of the list.
    let workspaces: [Workspace]
    /// The ID of the current workspace, or `nil`.
    let currentID: WorkspaceID?
    /// `false` when the library holds the most workspaces.
    let canCreate: Bool
    /// Switches to a workspace.
    let onSelect: (WorkspaceID) -> Void
    /// Starts a new workspace.
    let onCreate: () -> Void
    /// Starts the rename of a workspace.
    let onRename: (Workspace) -> Void
    /// Starts the delete of a workspace.
    let onDelete: (Workspace) -> Void
    /// The commands of the library below the workspaces, from the app (D-160).
    var commands: [LibraryCommand] = []
    /// Runs a command of the library.
    var onCommand: (LibraryCommand) -> Void = { _ in }

    /// The workspaces, the create row, and the commands.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView { workspaceRows }
                .frame(maxHeight: DesignSystem.Size.selectorListHeight)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            createRow
            if !commands.isEmpty {
                Divider()
                commandRows
            }
        }
        .modifier(ListWidth())
        .foregroundStyle(DesignSystem.Color.chromeForeground)
        .background(DesignSystem.Color.chromeBackground)
    }

    /// The rows of the workspaces, in their order.
    private var workspaceRows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(workspaces) { workspace in
                row(workspace)
            }
        }
    }

    private func row(_ workspace: Workspace) -> some View {
        let isCurrent = workspace.id == currentID
        return Button {
            onSelect(workspace.id)
        } label: {
            HStack(spacing: DesignSystem.Spacing.small) {
                Text(verbatim: workspace.title)
                    .font(DesignSystem.Font.chromeRow)
                    .modifier(RowLines())
                Spacer(minLength: DesignSystem.Spacing.small)
                if isCurrent {
                    // The row reads as selected, so VoiceOver skips the mark (D-179).
                    Image(systemName: DesignSystem.Icon.current)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .frame(minHeight: DesignSystem.Size.tapTarget)
            .background(isCurrent ? DesignSystem.Color.chromeSelection : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(WorkspaceStrings.rename, systemImage: DesignSystem.Icon.rename) {
                onRename(workspace)
            }
            Button(
                WorkspaceStrings.delete,
                systemImage: DesignSystem.Icon.delete,
                role: .destructive
            ) {
                onDelete(workspace)
            }
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        // The context menu needs a long press, so VoiceOver gets the same commands (D-179).
        .accessibilityAction(named: WorkspaceStrings.rename) { onRename(workspace) }
        .accessibilityAction(named: WorkspaceStrings.delete) { onDelete(workspace) }
    }

    private var commandRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commands) { command in
                Button {
                    onCommand(command)
                } label: {
                    Label(command.title, systemImage: command.systemImage)
                        .font(DesignSystem.Font.chromeRow)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: DesignSystem.Size.tapTarget,
                            alignment: .leading
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
    }

    private var createRow: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Button(action: onCreate) {
                Label(WorkspaceStrings.newWorkspace, systemImage: DesignSystem.Icon.create)
                    .font(DesignSystem.Font.chromeRow)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: DesignSystem.Size.tapTarget,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCreate)
            .accessibilityIdentifier("newWorkspace")
            if !canCreate {
                Text(verbatim: WorkspaceStrings.limitReached)
                    .font(DesignSystem.Font.chromeMessage)
                    .foregroundStyle(DesignSystem.Color.chromeSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, DesignSystem.Spacing.medium)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
    }
}

/// The width of the list, which grows with the text size up to
/// `DesignSystem.Size.selectorListMaxWidth` (D-179).
private struct ListWidth: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var width = DesignSystem.Size.selectorListWidth

    func body(content: Content) -> some View {
        content.frame(width: min(width, DesignSystem.Size.selectorListMaxWidth))
    }
}

/// One line per row, and 2 lines at an accessibility text size (D-179).
private struct RowLines: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
    }
}
