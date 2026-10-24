import Foundation
import Persistence

/// A message of a backup or a restore that did not work (task 3.2 of docs/m9-plan.md).
public enum BackupMessage: Error, Equatable, Sendable, CaseIterable {
    /// The picked file is no Pointer library: another file, another page size, version 0, or
    /// another schema (D-162).
    case notALibrary
    /// The picked file is damaged: `integrity_check` found a fault (D-162).
    case damaged
    /// The picked file comes from a newer version of Pointer (D-153).
    case newerVersion
    /// The picked file is an incomplete copy: it is in WAL mode, or its size is not whole
    /// pages (D-162).
    case incompleteCopy
    /// The disk has no room for the snapshot, the copy, or the restore.
    case diskFull
    /// The restore stopped before its end, and the library is as it was (D-164).
    case restoreStopped
    /// The save before the restore or before "Back up now" failed, so nothing ran (D-149).
    case saveFailed
    /// The restored library did not open, so Pointer put the library before the restore back
    /// (D-20, task 2.2 of docs/m9-plan.md).
    case restoreUndone
    /// "Back up now" did not write its snapshot (D-171).
    case backUpFailed

    /// Returns the message of a failed "Back up now": a full disk, or else `backUpFailed`
    /// (D-171).
    public init(backUp error: PersistenceError) {
        if case .diskFull = error { self = .diskFull } else { self = .backUpFailed }
    }

    /// Returns the message of a refused or failed restore.
    ///
    /// The checks of a picked file and the restore give these errors. Each other error is a
    /// fault of the copy, which the backup API rolls back, so it gives `restoreStopped`.
    public init(_ error: PersistenceError) {
        switch error {
        case .notADatabase, .wrongPageSize, .unknownVersion, .schemaMismatch: self = .notALibrary
        case .integrityFailed, .corruptValue, .corruptRow: self = .damaged
        case .newerSchema: self = .newerVersion
        case .walMode, .incompleteFile: self = .incompleteCopy
        case .diskFull: self = .diskFull
        default: self = .restoreStopped
        }
    }

    /// The text of the message, from the String Catalog of the package (STYLE-05).
    public var text: String {
        switch self {
        case .notALibrary:
            String(
                localized: "This file is not a Pointer library. Your library stays as it is.",
                bundle: .module
            )
        case .damaged:
            String(
                localized: "This file is damaged. Your library stays as it is.",
                bundle: .module
            )
        case .newerVersion:
            String(
                localized: """
                    This file comes from a newer version of Pointer. Update Pointer, and then \
                    restore the file again. Your library stays as it is.
                    """,
                bundle: .module
            )
        case .incompleteCopy:
            String(
                localized: """
                    This file is an incomplete copy of a library. Pick a snapshot from the \
                    Backups folder. Your library stays as it is.
                    """,
                bundle: .module
            )
        case .diskFull:
            String(
                localized: "The iPad has no room for this. Free some space, and try again.",
                bundle: .module
            )
        case .restoreStopped:
            String(
                localized: "The restore did not finish. Your library stays as it was.",
                bundle: .module
            )
        case .saveFailed:
            String(
                localized: "Pointer could not save your work, so nothing changed. Try again.",
                bundle: .module
            )
        case .restoreUndone:
            String(
                localized: """
                    The restored library did not open, so Pointer put back your library from \
                    before the restore.
                    """,
                bundle: .module
            )
        case .backUpFailed:
            String(
                localized: """
                    Pointer could not write the snapshot. Your library stays as it is. Try \
                    again.
                    """,
                bundle: .module
            )
        }
    }
}
