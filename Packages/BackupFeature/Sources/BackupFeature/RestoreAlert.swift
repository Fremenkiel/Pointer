import UIKit

/// The question before a restore (D-160): the restore replaces all workspaces, and Pointer
/// first saves the current library as a pre-restore snapshot in `Backups` (D-154).
public enum RestoreAlert {
    /// The title of the alert.
    public static var title: String {
        String(localized: "Restore from a snapshot?", bundle: .module)
    }

    /// The text of the alert.
    public static var message: String {
        String(
            localized: """
                The snapshot replaces all workspaces on this iPad. Pointer first saves your \
                current library as a pre-restore snapshot in the Backups folder.
                """,
            bundle: .module
        )
    }

    /// Returns the alert. `onRestore` runs after a tap of the restore button. A cancel does
    /// nothing.
    @MainActor
    public static func controller(onRestore: @escaping @MainActor () -> Void) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(title: String(localized: "Cancel", bundle: .module), style: .cancel)
        )
        alert.addAction(
            UIAlertAction(
                title: String(localized: "Choose a snapshot", bundle: .module),
                style: .destructive
            ) { _ in
                MainActor.assumeIsolated { onRestore() }
            }
        )
        return alert
    }
}
