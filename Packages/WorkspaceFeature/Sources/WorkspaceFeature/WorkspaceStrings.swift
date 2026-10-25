import Foundation
import Model

/// The user-facing text of the selector, from the String Catalog of the package (STYLE-05).
enum WorkspaceStrings {
    /// The title of the workspace that the app makes by itself (D-52).
    static var defaultTitle: String { String(localized: "Workspace", bundle: .module) }
    /// The title of the create row and the create dialog.
    static var newWorkspace: String { String(localized: "New Workspace", bundle: .module) }
    /// The title of the rename command of a workspace.
    static var rename: String { String(localized: "Rename", bundle: .module) }
    /// The title of the delete command and the delete button of a workspace.
    static var delete: String { String(localized: "Delete", bundle: .module) }
    /// The title of the cancel button of a dialog.
    static var cancel: String { String(localized: "Cancel", bundle: .module) }
    /// The title of the button that makes a new workspace.
    static var create: String { String(localized: "Create", bundle: .module) }
    /// The title of the button that saves a new name.
    static var save: String { String(localized: "Save", bundle: .module) }
    /// The placeholder of the name field.
    static var titlePlaceholder: String { String(localized: "Name", bundle: .module) }
    /// The title of the rename dialog.
    static var renameTitle: String { String(localized: "Rename Workspace", bundle: .module) }
    /// The title of the button that closes a message.
    static var ok: String { String(localized: "OK", bundle: .module) }
    /// The label of the workspace button.
    static var selectorLabel: String { String(localized: "Workspaces", bundle: .module) }
    /// The message when the library holds the most workspaces.
    static var limitReached: String {
        let limit = Limits.maxWorkspaces.formatted()
        return String(
            localized: "The library holds \(limit) workspaces. Delete one to make a new one.",
            bundle: .module
        )
    }
    /// The message when a name is empty or too long.
    static var invalidTitle: String {
        String(
            localized: "A name has 1 to \(Limits.maxTitleLength.formatted()) characters.",
            bundle: .module
        )
    }
    /// The message when the library opens read-only.
    static var readOnly: String {
        String(
            localized: "This library comes from a newer version of Pointer. It opens read-only.",
            bundle: .module
        )
    }
    /// The message when a change of a workspace does not save.
    static var storageFailed: String {
        String(localized: "Pointer could not save the change. Try again.", bundle: .module)
    }

    /// The question before a delete (D-11).
    static func deleteQuestion(_ title: String) -> String {
        String(localized: "Delete \"\(title)\" and all of its content?", bundle: .module)
    }
}
