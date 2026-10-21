import Foundation

/// The user-facing text of the canvas, from the String Catalog of the package (STYLE-05).
enum CanvasStrings {
    static var undo: String { String(localized: "Undo", bundle: .module) }
    static var redo: String { String(localized: "Redo", bundle: .module) }
    static var pen: String { String(localized: "Pen", bundle: .module) }
    static var eraser: String { String(localized: "Eraser", bundle: .module) }
    static var tools: String { String(localized: "Tools", bundle: .module) }
    static var text: String { String(localized: "Text", bundle: .module) }
    static var delete: String { String(localized: "Delete", bundle: .module) }
    static var textLimit: String {
        String(localized: "A text box holds at most 10,000 characters.", bundle: .module)
    }
    static var nodeLimit: String {
        String(localized: "This canvas holds no more cards or text boxes.", bundle: .module)
    }
    static var newCard: String { String(localized: "New card", bundle: .module) }
    static var rename: String { String(localized: "Rename", bundle: .module) }
    static var cancel: String { String(localized: "Cancel", bundle: .module) }
    static var titlePlaceholder: String { String(localized: "Title", bundle: .module) }
    static var titleLimit: String {
        String(localized: "A title holds at most 120 characters.", bundle: .module)
    }
    static var depthLimit: String {
        String(
            localized: "This canvas is at the deepest level. It holds no cards.",
            bundle: .module
        )
    }
}
