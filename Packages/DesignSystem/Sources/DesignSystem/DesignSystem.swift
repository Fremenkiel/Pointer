import SwiftUI
import UIKit

/// The design tokens of Pointer. UI code takes colors, sizes, and icons from here (STYLE-03).
public enum DesignSystem {
    /// The color tokens.
    public enum Color {
        /// The background of every canvas: black, with no paper texture (PEN-06).
        public static let canvasBackground: UIColor = .black
        /// The text and the icons of the controls on top of the canvas.
        public static let chromeForeground = SwiftUI.Color.white
        /// The background of the controls on top of the canvas: a dark gray that stands out from
        /// the black canvas.
        public static let chromeBackground = SwiftUI.Color(white: 0.14)
        /// The background of the selected row in a list of the chrome.
        public static let chromeSelection = SwiftUI.Color(white: 0.26)
        /// The text of a secondary line, for example a message.
        public static let chromeSecondary = SwiftUI.Color(white: 0.65)
        /// The icon of a control that is off, for example undo with an empty history.
        public static let chromeDisabled = SwiftUI.Color(white: 0.4)
    }

    /// The spacing tokens, in points.
    public enum Spacing {
        /// The gap between an icon and its text.
        public static let small: CGFloat = 6
        /// The inner margin of a control.
        public static let medium: CGFloat = 12
        /// The distance of a control from the screen edge.
        public static let large: CGFloat = 16
    }

    /// The size tokens, in points.
    public enum Size {
        /// The smallest height of a control that a finger taps: 44 points, from the Apple Human
        /// Interface Guidelines.
        public static let tapTarget: CGFloat = 44
        /// The corner radius of the controls on top of the canvas.
        public static let cornerRadius: CGFloat = 10
        /// The width of the workspace list.
        public static let selectorListWidth: CGFloat = 300
        /// The widest title in the workspace button. A longer title ends with an ellipsis.
        public static let selectorTitleWidth: CGFloat = 260
        /// The highest workspace list before it scrolls.
        public static let selectorListHeight: CGFloat = 480
    }

    /// The font tokens.
    public enum Font {
        /// The title in a control of the chrome.
        public static let chromeTitle = SwiftUI.Font.headline
        /// A row in a list of the chrome.
        public static let chromeRow = SwiftUI.Font.body
        /// A message under a list.
        public static let chromeMessage = SwiftUI.Font.footnote
    }

    /// The icon tokens: names of SF Symbols.
    public enum Icon {
        /// Opens a list.
        public static let expand = "chevron.down"
        /// Marks the current item.
        public static let current = "checkmark"
        /// Makes a new item.
        public static let create = "plus"
        /// Renames an item.
        public static let rename = "pencil"
        /// Deletes an item.
        public static let delete = "trash"
        /// Undoes the last step (UNDO-01).
        public static let undo = "arrow.uturn.backward"
        /// Redoes the last undone step (UNDO-01).
        public static let redo = "arrow.uturn.forward"
        /// The pen tool (TOOL-01).
        public static let pen = "pencil.tip"
        /// The eraser tool (TOOL-01).
        public static let eraser = "eraser"
        /// The text tool (TOOL-01, D-87).
        public static let text = "character.cursor.ibeam"
    }
}
