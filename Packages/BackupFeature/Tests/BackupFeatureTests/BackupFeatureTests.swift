import Persistence
import Testing
import UIKit

@testable import BackupFeature

/// The commands, the messages, the alert, and the picker of the backup (tasks 3.1 and 3.2 of
/// the M9 plan). They run in PointerDeviceTests on the iPad (D-77).
@MainActor
@Suite("Backup feature")
struct BackupFeatureTests {
    @Test(
        "Each refusal reason gives its message",
        arguments: [
            (PersistenceError.notADatabase, BackupMessage.notALibrary),
            (.wrongPageSize(bytes: 8192), .notALibrary),
            (.unknownVersion(0), .notALibrary),
            (.schemaMismatch(reason: "extra trigger"), .notALibrary),
            (.integrityFailed(reason: "row 1 missing"), .damaged),
            (.newerSchema(version: 2), .newerVersion),
            (.walMode, .incompleteCopy),
            (.incompleteFile(byteCount: 100), .incompleteCopy),
            (.diskFull, .diskFull),
            (.restoreStopped, .restoreStopped),
            (.sqlite(code: 10, message: "disk I/O error"), .restoreStopped),
        ]
    )
    func message(error: PersistenceError, message: BackupMessage) {
        #expect(BackupMessage(error) == message)
    }

    @Test(
        "A failed back-up gives its own message, or the message of a full disk (D-171)",
        arguments: [
            (
                PersistenceError.sqlite(code: 10, message: "disk I/O error"),
                BackupMessage.backUpFailed
            ),
            (.fileFailed(reason: "rename"), .backUpFailed),
            (.diskFull, .diskFull),
        ]
    )
    func backUpMessage(error: PersistenceError, message: BackupMessage) {
        #expect(BackupMessage(backUp: error) == message)
    }

    @Test("Each message and each command has a text from the String Catalog")
    func texts() {
        let texts = BackupMessage.allCases.map(\.text) + BackupCommand.allCases.map(\.title)
        #expect(texts.allSatisfy { !$0.isEmpty })
        #expect(Set(texts).count == texts.count, "Each text differs")
        #expect(BackupCommand.backUpNow.title == "Back up now")
    }

    @Test("The alert before a restore offers a cancel and the choice of a snapshot (D-160)")
    func alert() {
        var isRestored = false
        let alert = RestoreAlert.controller { isRestored = true }
        #expect(alert.title == RestoreAlert.title)
        #expect(alert.message?.contains("pre-restore snapshot") == true)
        #expect(alert.actions.map(\.style) == [.cancel, .destructive])
        #expect(!isRestored)
    }

    @Test("The picker opens snapshot files in place, one at a time (D-156)")
    func picker() {
        var picked: [URL] = []
        let picker = SnapshotPicker { picked.append($0) }
        let controller = picker.controller()
        #expect(SnapshotPicker.snapshotType.identifier == "dk.saarikivi.pointer.snapshot")
        #expect(SnapshotPicker.snapshotType.conforms(to: .database))
        #expect(!controller.allowsMultipleSelection)
        let url = URL(filePath: "/tmp/Pointer-2026-10-24-120000.sqlite")
        picker.documentPicker(controller, didPickDocumentsAt: [url])
        #expect(picked == [url])
    }

    @Test("A picker goes with its view, also without a pick or a cancel (review after M9)")
    func pickerGoesWithItsView() {
        weak var weakPicker: SnapshotPicker?
        var controller: UIDocumentPickerViewController?
        do {
            let picker = SnapshotPicker { _ in }
            weakPicker = picker
            controller = picker.controller()
        }
        #expect(controller?.delegate === weakPicker, "The view keeps its delegate")
        #expect(weakPicker != nil)
        controller = nil
        #expect(weakPicker == nil, "A dismissed picker keeps no delegate and no closure")
    }

    @Test("The share sheet takes the snapshot file")
    func share() {
        let url = URL(filePath: "/tmp/Pointer-2026-10-24-120000.sqlite")
        let sheet = SnapshotShare.controller(for: url) {}
        #expect(sheet.completionWithItemsHandler != nil)
    }
}
