import BackupFeature
import Foundation
import WorkspaceFeature

/// The commands of the library in the list of the selector (task 3.1 of the M9 plan,
/// D-160). The handlers stay thin: the flows behind them have their own tests.
extension AppComposition {
    /// Returns "Back up now" and "Restore from a snapshot".
    func libraryCommands() -> [LibraryCommand] {
        BackupCommand.allCases.map { command in
            LibraryCommand(
                id: command.rawValue,
                title: command.title,
                systemImage: command.systemImage
            ) { [weak self] in
                switch command {
                case .backUpNow: self?.startBackUpNow()
                case .restore: self?.askForRestore()
                }
            }
        }
    }

    /// Writes the snapshot and opens the share sheet at the selector (STO-04).
    private func startBackUpNow() {
        Task {
            switch await backUpNow() {
            case .success(let url): share(url, at: container.selectorFrame)
            case .failure(let message): container.showMessage(message.text)
            case nil: break
            }
        }
    }

    /// Asks before a restore, then opens the picker (D-156, D-160).
    private func askForRestore() {
        guard !isLibraryBusy else { return }
        let alert = RestoreAlert.controller { [weak self] in self?.pickSnapshot() }
        container.present(alert, animated: true)
    }

    private func pickSnapshot() {
        let picker = SnapshotPicker { [weak self] url in
            guard let self else { return }
            Task { await self.restore(from: url) }
        }
        container.present(picker.controller(), animated: true)
    }
}
