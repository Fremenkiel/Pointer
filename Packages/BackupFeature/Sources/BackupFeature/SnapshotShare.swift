import UIKit

/// The share sheet of "Back up now" (STO-04, D-160).
public enum SnapshotShare {
    /// Returns a share sheet for the snapshot file at `url`. On iPad it shows in a popover, so
    /// the caller sets the anchor of `popoverPresentationController`
    /// (<https://developer.apple.com/documentation/uikit/uiactivityviewcontroller>).
    ///
    /// - Precondition: `url` is a file URL.
    @MainActor
    public static func controller(
        for url: URL,
        completion: @escaping @MainActor () -> Void
    ) -> UIActivityViewController {
        precondition(url.isFileURL, "A snapshot is a file, got \(url)")
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, _, _, _ in
            MainActor.assumeIsolated { completion() }
        }
        return sheet
    }
}
