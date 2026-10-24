import DesignSystem
import Foundation

/// The two commands of the backup in the list of the workspace selector (D-160).
public enum BackupCommand: String, CaseIterable, Sendable {
    /// Saves, writes a snapshot, and opens the share sheet (STO-04).
    case backUpNow
    /// Asks, then opens the document picker for a snapshot (D-20).
    case restore

    /// The text of the row, from the String Catalog of the package (STYLE-05).
    public var title: String {
        switch self {
        case .backUpNow: String(localized: "Back up now", bundle: .module)
        case .restore: String(localized: "Restore from a snapshot", bundle: .module)
        }
    }

    /// The SF Symbol of the row (STYLE-03).
    public var systemImage: String {
        switch self {
        case .backUpNow: DesignSystem.Icon.backUp
        case .restore: DesignSystem.Icon.restore
        }
    }
}
