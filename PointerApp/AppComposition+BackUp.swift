import BackupFeature
import Foundation
import Persistence
import UIKit

/// "Back up now" (task 2.4 of the M9 plan, STO-04, D-155, D-160).
extension AppComposition {
    /// Saves the work on the screen and writes a daily snapshot for the share sheet (D-149,
    /// D-155). The screen takes no input until the end (D-169).
    ///
    /// - Returns: The snapshot in `Documents/Backups/`, the message of a failure, or `nil` if a
    ///   restore or a back-up runs already.
    func backUpNow() async -> Result<URL, BackupMessage>? {
        guard beginLibraryWork() else { return nil }
        defer { endLibraryWork() }
        guard let writer else { return .failure(.saveFailed) }
        do {
            try await saveWorkOnScreen()
        } catch {
            return .failure(.saveFailed)
        }
        do throws(PersistenceError) {
            return .success(try await writer.writeSnapshotNow())
        } catch {
            logger.error("The snapshot of \"Back up now\" failed: \(error)")
            return .failure(BackupMessage(backUp: error))
        }
    }

    /// Shows the share sheet of `snapshot` in a popover at `anchor` in the container. The idle
    /// snapshot waits until the sheet closes, so the rotation never deletes the shared file
    /// while the user picks a target (task 2.4, item 3).
    ///
    /// The flag is set when the sheet shows. A sheet that UIKit does not show thus does not stop
    /// the daily snapshot for the rest of the run (review after M9).
    func share(_ snapshot: URL, at anchor: CGRect) {
        precondition(snapshot.isFileURL, "A snapshot is a file, got \(snapshot)")
        let sheet = SnapshotShare.controller(for: snapshot) { [weak self] in
            self?.isSharing = false
            self?.sharedSnapshot = nil
        }
        sheet.popoverPresentationController?.sourceView = container.view
        sheet.popoverPresentationController?.sourceRect = anchor
        container.presentOnTop(sheet) { [weak self] in
            self?.isSharing = true
            self?.sharedSnapshot = snapshot
        }
    }
}
