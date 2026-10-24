import BackupFeature
import Foundation
import Model
import Persistence
import UIKit

/// The restore from a picked snapshot (task 2.3 of docs/m9-plan.md, storage.md section 7.5,
/// D-148, D-149, D-154, D-164).
extension AppComposition {
    /// The outcome of a restore, for the message and for the tests.
    enum RestoreOutcome: Equatable {
        /// The library holds the snapshot, and a new composition replaces this one.
        case restored
        /// The checks refused the file, or a step before the copy failed. The library and the
        /// screen stay as they were.
        case refused(BackupMessage)
        /// The copy did not finish and rolled back. A new composition opens the old library.
        case stopped(BackupMessage)
        /// A restore or "Back up now" ran already, so this restore did nothing (D-169).
        case ignored
    }

    /// Restores the library from a picked file (D-148).
    ///
    /// The order: copy and check the file, save the work on the screen (D-149), write the
    /// pre-restore snapshot (D-154), close the screens, and copy with extra time in the
    /// background. At the end of that time, the stop flag rolls the copy back (D-164). After
    /// the copy, a new composition opens the library as at launch, and it shows the message
    /// of a stop.
    ///
    /// The screen takes no input from the start to the end (D-169). A library of a newer
    /// schema takes the restore too (D-168).
    ///
    /// - Returns: The outcome. A refusal shows its message at once.
    @discardableResult  // The command needs no result. The tests read it.
    func restore(from picked: URL) async -> RestoreOutcome {
        guard beginLibraryWork() else { return .ignored }
        guard let repository, let writer, let files = openedFiles else {
            return refuse(.restoreStopped)
        }
        let importer = SnapshotImport(temporaryFolder: files.temporary)
        let checked: CheckedSnapshot
        do throws(PersistenceError) {
            checked = try await importer.copyAndCheck(picked)
        } catch {
            return refuse(BackupMessage(error))
        }
        do {
            try await saveWorkOnScreen()
        } catch {
            await importer.discard(checked)
            return refuse(.saveFailed)
        }
        let fallback: URL
        do throws(PersistenceError) {
            fallback = try await writer.writePreRestoreSnapshot()
        } catch {
            await importer.discard(checked)
            return refuse(BackupMessage(error))
        }
        let outcome = await copy(checked, into: repository)
        await importer.discard(checked)
        await closeFilesAfterRestore()
        replace(after: outcome, fallback: fallback)
        return outcome
    }

    /// Closes the screens and copies the checked file into the library with extra time in the
    /// background. The library is closed after it, also after a stop.
    private func copy(
        _ checked: CheckedSnapshot,
        into repository: SQLiteLibraryRepository
    ) async -> RestoreOutcome {
        await closeScreens()
        // The cache goes before the copy, so that a stop of the process after the copy does
        // not show the previews of the old library (D-157, review after M9).
        await clearPreviews()
        let stop = RestoreStop()
        let extraTime = ExtraTime("Restore", time: backgroundTime) { stop.stop() }
        defer { extraTime.end() }
        do throws(PersistenceError) {
            try await repository.restore(from: checked, stop: stop)
            return .restored
        } catch {
            logger.error("The restore did not finish: \(error)")
            return .stopped(BackupMessage(error))
        }
    }

    /// Shows the message of a refused restore and lets the canvas take edits again.
    private func refuse(_ message: BackupMessage) -> RestoreOutcome {
        endLibraryWork()
        container.showMessage(message.text)
        return .refused(message)
    }

    /// Hands the app to a new composition. After a restore, the pre-restore snapshot is the way
    /// back if the restored library does not open (D-20).
    private func replace(after outcome: RestoreOutcome, fallback: URL) {
        let message: String?
        if case .stopped(let reason) = outcome { message = reason.text } else { message = nil }
        let handoff = Handoff(
            lastClock: clock?.factory.clock.last,
            message: message,
            fallback: outcome == .restored ? fallback : nil
        )
        onReplace?(handoff)
    }

    /// Restores the pre-restore snapshot after the restored library did not open, and hands
    /// the app to a new composition with a message (task 2.2, item 4).
    ///
    /// - Returns: `false` if the way back failed too.
    func undoRestore(from fallback: URL, files: AppFiles, handoff: Handoff) async -> Bool {
        guard let repository else { return false }
        let importer = SnapshotImport(temporaryFolder: files.temporary)
        do {
            let checked = try await importer.copyAndCheck(fallback)
            try await repository.restore(from: checked, stop: RestoreStop())
            await importer.discard(checked)
        } catch {
            logger.fault("The way back after a failed restore failed: \(error)")
            return false
        }
        await closeFilesAfterRestore()
        onReplace?(
            Handoff(
                lastClock: handoff.lastClock,
                message: BackupMessage.restoreUndone.text,
                fallback: nil
            )
        )
        return true
    }
}
