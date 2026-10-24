/// A command of the whole library that the app puts into the list of the selector, for
/// example "Back up now" (D-160). The selector knows no type of another feature (ARCH-02).
public struct LibraryCommand: Identifiable {
    /// A name that stays the same for the command.
    public let id: String
    /// The text of the row, from the String Catalog of the feature that gives it (STYLE-05).
    public let title: String
    /// The SF Symbol of the row, from `DesignSystem.Icon` (STYLE-03).
    public let systemImage: String
    /// Runs the command after the list closes.
    public let action: @MainActor () -> Void

    /// Makes a command.
    ///
    /// - Precondition: `id` and `title` are not empty.
    public init(
        id: String,
        title: String,
        systemImage: String,
        action: @escaping @MainActor () -> Void
    ) {
        precondition(!id.isEmpty && !title.isEmpty, "A command needs a name and a title")
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}
