import BackupFeature
import Foundation
import Persistence
import UIKit

/// "Back up now" (task 2.4 of docs/m9-plan.md, STO-04, D-155, D-160).
extension AppComposition {
    /// Saves the work on the screen and writes a daily snapshot for the share sheet (D-149,
    /// D-155).
    ///
    /// - Returns: The snapshot in `Documents/Backups/`, or the message of a failure.
    func backUpNow() async -> Result<URL, BackupMessage> {
        defer { resumeEditing() }
        guard let writer else { return .failure(.saveFailed) }
        do {
            try await saveWorkOnScreen()
        } catch {
            return .failure(.saveFailed)
        }
        do throws(PersistenceError) {
            return .success(try await writer.writeSnapshotNow())
        } catch {
            return .failure(BackupMessage(error))
        }
    }

    /// Shows the share sheet of `snapshot` in a popover at `anchor` in the container. The idle
    /// snapshot waits until the sheet closes, so the rotation never deletes the shared file
    /// while the user picks a target (task 2.4, item 3).
    func share(_ snapshot: URL, at anchor: CGRect) {
        precondition(snapshot.isFileURL, "A snapshot is a file, got \(snapshot)")
        isSharing = true
        sharedSnapshot = snapshot
        let sheet = SnapshotShare.controller(for: snapshot) { [weak self] in
            self?.isSharing = false
            self?.sharedSnapshot = nil
        }
        sheet.popoverPresentationController?.sourceView = container.view
        sheet.popoverPresentationController?.sourceRect = anchor
        container.present(sheet, animated: true)
    }
}
