import DesignSystem
import Model
import SwiftUI

/// The list of all workspaces with the commands to switch, create, rename, and delete (WS-02,
/// WS-03).
struct WorkspaceList: View {
    let workspaces: [Workspace]
    let currentID: WorkspaceID?
    let canCreate: Bool
    let onSelect: (WorkspaceID) -> Void
    let onCreate: () -> Void
    let onRename: (Workspace) -> Void
    let onDelete: (Workspace) -> Void
    /// The commands of the library below the workspaces, from the app (D-160).
    var commands: [LibraryCommand] = []
    /// Runs a command of the library.
    var onCommand: (LibraryCommand) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(workspaces) { workspace in
                        row(workspace)
                    }
                }
            }
            .frame(maxHeight: DesignSystem.Size.selectorListHeight)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            createRow
            if !commands.isEmpty {
                Divider()
                commandRows
            }
        }
        .frame(width: DesignSystem.Size.selectorListWidth)
        .foregroundStyle(DesignSystem.Color.chromeForeground)
        .background(DesignSystem.Color.chromeBackground)
    }

    private func row(_ workspace: Workspace) -> some View {
        let isCurrent = workspace.id == currentID
        return Button {
            onSelect(workspace.id)
        } label: {
            HStack(spacing: DesignSystem.Spacing.small) {
                Text(verbatim: workspace.title)
                    .font(DesignSystem.Font.chromeRow)
                    .lineLimit(1)
                Spacer(minLength: DesignSystem.Spacing.small)
                if isCurrent {
                    Image(systemName: DesignSystem.Icon.current)
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
