import DesignSystem
import Model
import SwiftUI

/// The workspace selector in the top left corner (WS-01 to WS-03).
///
/// A tap on the button shows the list. A long press on a row offers rename and delete. A delete
/// asks for a confirmation first (D-11).
public struct WorkspaceSelectorView: View {
    /// The name dialog that is open.
    private enum Editor: Identifiable {
        case create
        case rename(Workspace)

        var id: String {
            switch self {
            case .create: "create"
            case .rename(let workspace): workspace.id.description
            }
        }
    }

    @Bindable private var model: WorkspaceSelectorModel
    @State private var isListShown = false
    @State private var editor: Editor?
    @State private var title = ""
    @State private var pendingDelete: Workspace?

    /// Makes the selector of `model`.
    public init(model: WorkspaceSelectorModel) {
        self.model = model
    }

    /// The button, the list, and the dialogs.
    public var body: some View {
        WorkspaceButton(title: model.current?.title ?? "") { isListShown = true }
            .popover(isPresented: $isListShown) {
                list.presentationCompactAdaptation(.popover)
            }
            .alert(editorTitle, isPresented: isEditorShown) {
                TextField(WorkspaceStrings.titlePlaceholder, text: $title)
                Button(WorkspaceStrings.cancel, role: .cancel) {}
                Button(editorAction) { commitEditor() }
            }
            .confirmationDialog(
                deleteQuestion,
                isPresented: isDeleteShown,
                titleVisibility: .visible
            ) {
                Button(WorkspaceStrings.delete, role: .destructive) { commitDelete() }
                Button(WorkspaceStrings.cancel, role: .cancel) {}
            }
            .alert(model.message?.text ?? "", isPresented: isMessageShown) {
                Button(WorkspaceStrings.ok) { model.dismissMessage() }
            }
    }

    private var list: some View {
        WorkspaceList(
            workspaces: model.workspaces,
            currentID: model.current?.id,
            canCreate: model.canCreate,
            onSelect: { id in
                model.select(id)
                isListShown = false
            },
            onCreate: {
                title = ""
                editor = .create
            },
            onRename: { workspace in
                title = workspace.title
                editor = .rename(workspace)
            },
            onDelete: { workspace in pendingDelete = workspace }
        )
    }

    private var editorTitle: String {
        if case .rename = editor { return WorkspaceStrings.renameTitle }
        return WorkspaceStrings.newWorkspace
    }

    private var editorAction: String {
        if case .rename = editor { return WorkspaceStrings.save }
        return WorkspaceStrings.create
    }

    private var deleteQuestion: String {
        WorkspaceStrings.deleteQuestion(pendingDelete?.title ?? "")
    }

    private var isEditorShown: Binding<Bool> {
        Binding(get: { editor != nil }, set: { if !$0 { editor = nil } })
    }

    private var isDeleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var isMessageShown: Binding<Bool> {
        Binding(get: { model.message != nil }, set: { if !$0 { model.dismissMessage() } })
    }

    private func commitEditor() {
        let text = title
        let action = editor
        editor = nil
        Task {
            switch action {
            case .create: await model.create(title: text)
            case .rename(let workspace): await model.rename(workspace.id, to: text)
            case nil: break
            }
        }
    }

    private func commitDelete() {
        guard let workspace = pendingDelete else { return }
        pendingDelete = nil
        Task { await model.delete(workspace.id) }
    }
}
