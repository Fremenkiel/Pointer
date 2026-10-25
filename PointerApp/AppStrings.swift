import Foundation

/// The user-facing text of the app target, from its String Catalog (STYLE-05).
enum AppStrings {
    /// The title of the button that closes a message.
    static var ok: String { String(localized: "OK") }
    /// The message when the library does not open.
    static var libraryFailed: String {
        String(localized: "Pointer could not open its library. Your data stays as it is.")
    }
    /// The message when the library opens read-only.
    static var readOnly: String {
        String(
            localized: "This library comes from a newer version of Pointer. It opens read-only."
        )
    }
    /// The message while the saves fail.
    static var savesFailing: String {
        String(
            localized: """
                Pointer cannot save. Drawing stops until a save works again. \
                Your work so far is safe.
                """
        )
    }
    /// The message when a canvas skips damaged rows.
    static var rowsSkipped: String {
        String(localized: "Some content of this canvas is damaged and does not show.")
    }
    /// The message when a workspace does not open.
    static var canvasFailed: String {
        String(localized: "Pointer could not open this workspace.")
    }
}
