import SwiftUI
import UIKit

/// The design tokens of Pointer. UI code takes colors, sizes, and icons from here (STYLE-03).
public enum DesignSystem {
    /// The color tokens.
    public enum Color {
        /// The background of every canvas in sRGB, each channel from 0 to 1: RGB(24, 24, 24),
        /// with no paper texture (CAN-01, PEN-06, D-106). The renderer takes these values.
        public static let canvasBackgroundSRGB = SIMD3<Float>(repeating: 24) / 255
        /// The background of every canvas as a color for the views (CAN-01, D-106).
        public static let canvasBackground = UIColor(
            red: CGFloat(canvasBackgroundSRGB.x),
            green: CGFloat(canvasBackgroundSRGB.y),
            blue: CGFloat(canvasBackgroundSRGB.z),
            alpha: 1
        )
        /// The coverage of the border of a card, below 1, so that the border shows gray on the
        /// canvas color: 0.5 mixes RGB(24, 24, 24) and white to about RGB(140, 140, 140)
        /// (architecture.md 5.5, D-96). The renderer takes this value.
        public static let cardBorder: Float = 0.5
        /// The coverage of the body of a card: a light gray on the canvas color, about RGB(39,
        /// 39, 39), the step of the card body over the canvas in Allume (RGB 35 on RGB 20, D-116).
        public static let cardFill: Float = 0.065
        /// The ink of the pen and the text on the canvas: white, with no conversion in the live
        /// stroke of PencilKit (TOOL-02, D-15, D-38).
        public static let ink = UIColor.white
        /// The text and the icons of the controls on top of the canvas.
        public static let chromeForeground = SwiftUI.Color.white
        /// The background of the controls on top of the canvas: a dark gray, a little brighter than
        /// the canvas color of D-106.
        public static let chromeBackground = SwiftUI.Color(white: 0.14)
        /// The background of the selected row in a list of the chrome.
        public static let chromeSelection = SwiftUI.Color(white: 0.26)
        /// The text of a secondary line, for example a message.
        public static let chromeSecondary = SwiftUI.Color(white: 0.65)
        /// The icon of a control that is off, for example undo with an empty history.
        public static let chromeDisabled = SwiftUI.Color(white: 0.4)
        /// The hover dot of the pencil and the eraser circle: the gray of a secondary line of the
        /// chrome (D-128). A start value that the product owner tunes on the device.
        public static let hoverDot = UIColor(chromeSecondary)
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
        /// The widest workspace list at a large text size: twice `selectorListWidth`, inside the
        /// 744-point width of the smallest iPad in portrait (D-179). The text of a row wraps.
        public static let selectorListMaxWidth: CGFloat = 600
        /// The radius of the hover dot of the pen and the text tool, in view points (D-128). A
        /// start value that the product owner tunes on the device.
        public static let hoverDotRadius: CGFloat = 2
        /// The line width of the eraser circle of the hover dot, in view points (D-133). A start
        /// value that the product owner tunes on the device.
        public static let hoverRingWidth: CGFloat = 1
        /// The points of the dot of a pen width button per canvas point of the width, so that the
        /// three widths of TOOL-09 show as dots of 3, 6, and 12 points (D-199).
        public static let penWidthDotScale: CGFloat = 3
    }

    /// The font tokens.
    public enum Font {
        /// A row in a list of the chrome.
        public static let chromeRow = SwiftUI.Font.body
        /// A message under a list.
        public static let chromeMessage = SwiftUI.Font.footnote
        /// The symbol of an icon button and the title of the workspace button: the size of
        /// `headline` at the standard text size. It does not grow with the text size, because the
        /// bar keeps its height. The Large Content Viewer shows the button large (D-179).
        public static let chromeBar = SwiftUI.Font.system(size: 17, weight: .semibold)
        /// The small symbol of the workspace button: the size of `footnote` at the standard text
        /// size, fixed as `chromeBar` (D-179).
        public static let chromeBarDetail = SwiftUI.Font.system(size: 13)
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
        /// Exports the canvas as a PDF (EXP-01).
        public static let export = "square.and.arrow.up"
        /// Clears the canvas: all ink, text boxes, and cards go (TOOL-10, D-200). The symbol of
        /// `delete`, because the button removes items.
        public static let clearCanvas = "trash"
        /// The pen tool (TOOL-01).
        public static let pen = "pencil.tip"
        /// The eraser tool (TOOL-01).
        public static let eraser = "eraser"
        /// The text tool (TOOL-01, D-87).
        public static let text = "character.cursor.ibeam"
        /// Makes a new card (CARD-01, D-117).
        public static let card = "rectangle.badge.plus"
        /// Leaves the current card for its parent canvas (CARD-04).
        public static let up = "arrow.up.left"
        /// Writes a snapshot and shares it: "Back up now" (STO-04, D-160).
        public static let backUp = "externaldrive.badge.checkmark"
        /// Restores the library from a snapshot (D-20, D-160).
        public static let restore = "clock.arrow.circlepath"
    }
}
