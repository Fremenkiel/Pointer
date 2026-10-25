import Foundation

/// The user-facing text of the canvas, from the String Catalog of the package (STYLE-05).
enum CanvasStrings {
    /// The label of the undo button.
    static var undo: String { String(localized: "Undo", bundle: .module) }
    /// The label of the redo button.
    static var redo: String { String(localized: "Redo", bundle: .module) }
    /// The label of the export button.
    static var export: String { String(localized: "Export", bundle: .module) }
    /// The message when an export finds no ink and no text on the canvas.
    static var exportEmpty: String {
        String(localized: "This canvas holds no ink and no text to export.", bundle: .module)
    }
    /// The message when the PDF of an export fails.
    static var exportFailed: String {
        String(localized: "The PDF could not be made.", bundle: .module)
    }
    /// The name of the pen tool.
    static var pen: String { String(localized: "Pen", bundle: .module) }
    /// The name of the eraser tool.
    static var eraser: String { String(localized: "Eraser", bundle: .module) }
    /// The label of the current-tool button.
    static var tools: String { String(localized: "Tools", bundle: .module) }
    /// The name of the text tool.
    static var text: String { String(localized: "Text", bundle: .module) }
    /// The title of the delete command of a card or a text box.
    static var delete: String { String(localized: "Delete", bundle: .module) }
    /// The message when a text box reaches its character limit.
    static var textLimit: String {
        String(localized: "A text box holds at most 10,000 characters.", bundle: .module)
    }
    /// The message when the canvas holds the most cards and text boxes.
    static var nodeLimit: String {
        String(localized: "This canvas holds no more cards or text boxes.", bundle: .module)
    }
    /// The label of the new card button.
    static var newCard: String { String(localized: "New card", bundle: .module) }
    /// The title of the rename command and the rename dialog of a card.
    static var rename: String { String(localized: "Rename", bundle: .module) }
    /// The label of the button that goes up to the parent canvas.
    static var up: String { String(localized: "Up", bundle: .module) }
    /// The title of the cancel button of the rename dialog of a card.
    static var cancel: String { String(localized: "Cancel", bundle: .module) }
    /// The placeholder of the title field of a card.
    static var titlePlaceholder: String { String(localized: "Title", bundle: .module) }
    /// The message when a card title reaches its character limit.
    static var titleLimit: String {
        String(localized: "A title holds at most 120 characters.", bundle: .module)
    }
    /// The message when a new card would go below the deepest level.
    static var depthLimit: String {
        String(
            localized: "This canvas is at the deepest level. It holds no cards.",
            bundle: .module
        )
    }
}
