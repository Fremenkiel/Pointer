import Foundation

/// The user-facing text of the app target, from its String Catalog (STYLE-05).
enum AppStrings {
    static var ok: String { String(localized: "OK") }
    static var libraryFailed: String {
        String(localized: "Pointer could not open its library. Your data stays as it is.")
    }
    static var readOnly: String {
        String(
            localized: "This library comes from a newer version of Pointer. It opens read-only."
        )
    }
    static var savesFailing: String {
        String(
            localized: """
                Pointer cannot save. Drawing stops until a save works again. \
                Your work so far is safe.
                """
        )
    }
    static var rowsSkipped: String {
        String(localized: "Some content of this canvas is damaged and does not show.")
    }
    static var canvasFailed: String {
        String(localized: "Pointer could not open this workspace.")
    }
}
