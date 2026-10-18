import Foundation

/// The user-facing text of the selector, from the String Catalog of the package (STYLE-05).
enum WorkspaceStrings {
    /// The title of the workspace that the app makes by itself (D-52).
    static var defaultTitle: String { String(localized: "Workspace", bundle: .module) }
    static var newWorkspace: String { String(localized: "New Workspace", bundle: .module) }
    static var rename: String { String(localized: "Rename", bundle: .module) }
    static var delete: String { String(localized: "Delete", bundle: .module) }
    static var cancel: String { String(localized: "Cancel", bundle: .module) }
    static var create: String { String(localized: "Create", bundle: .module) }
    static var save: String { String(localized: "Save", bundle: .module) }
    static var titlePlaceholder: String { String(localized: "Name", bundle: .module) }
    static var renameTitle: String { String(localized: "Rename Workspace", bundle: .module) }
    static var ok: String { String(localized: "OK", bundle: .module) }
    static var selectorLabel: String { String(localized: "Workspaces", bundle: .module) }
    static var limitReached: String {
        String(
            localized: "The library holds 1,000 workspaces. Delete one to make a new one.",
            bundle: .module
        )
    }
    static var invalidTitle: String {
        String(localized: "A name has 1 to 120 characters.", bundle: .module)
    }
    static var readOnly: String {
        String(
            localized: "This library comes from a newer version of Pointer. It opens read-only.",
            bundle: .module
        )
    }
    static var storageFailed: String {
        String(localized: "Pointer could not save the change. Try again.", bundle: .module)
    }

    /// The question before a delete (D-11).
    static func deleteQuestion(_ title: String) -> String {
        String(localized: "Delete \"\(title)\" and all of its content?", bundle: .module)
    }
}
