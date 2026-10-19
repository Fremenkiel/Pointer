import Foundation

/// The user-facing text of the canvas, from the String Catalog of the package (STYLE-05).
enum CanvasStrings {
    static var undo: String { String(localized: "Undo", bundle: .module) }
    static var redo: String { String(localized: "Redo", bundle: .module) }
    static var pen: String { String(localized: "Pen", bundle: .module) }
    static var eraser: String { String(localized: "Eraser", bundle: .module) }
    static var tools: String { String(localized: "Tools", bundle: .module) }
}
