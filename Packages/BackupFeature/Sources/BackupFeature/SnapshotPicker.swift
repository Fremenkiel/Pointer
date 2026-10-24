import UIKit
import UniformTypeIdentifiers

/// The document picker of a restore (D-156). It opens the picked file in place
/// (`asCopy: false`), so the URL has a security scope, and `Persistence` copies the file
/// (<https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller>).
@MainActor
public final class SnapshotPicker: NSObject, UIDocumentPickerDelegate {
    /// The type of a snapshot that `Info.plist` declares for `.sqlite` (D-156).
    public static let snapshotType = UTType(importedAs: "dk.saarikivi.pointer.snapshot")

    private let onPick: @MainActor (URL) -> Void
    /// The picker keeps its delegate until a pick or a cancel, because UIKit holds it weakly.
    private var keepsItself: SnapshotPicker?

    /// Makes a picker. `onPick` runs with the URL of the picked file.
    public init(onPick: @escaping @MainActor (URL) -> Void) {
        self.onPick = onPick
    }

    /// Returns the picker view of one snapshot file, with this object as its delegate.
    public func controller() -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [Self.snapshotType],
            asCopy: false
        )
        picker.allowsMultipleSelection = false
        picker.delegate = self
        keepsItself = self
        return picker
    }

    /// Passes the picked file on.
    public func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        keepsItself = nil
        guard let url = urls.first else { return }
        onPick(url)
    }

    /// Ends the pick without a file.
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        keepsItself = nil
    }
}
