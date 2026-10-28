import Geometry
import Model
import Rendering
import UIKit

/// The state of the text tools of one canvas: the edit view, the running edit, the move of a box,
/// the long-press menu, and the sizes of the boxes for the hit test (architecture.md section 7).
/// The state of the cards is in `CardInteraction`.
@MainActor
final class TextEditing {
    /// One running edit.
    struct Edit {
        /// The ID of the box. A new box has a new ID.
        let id: TextBoxID
        /// The box before the edit, or `nil` for a new box.
        let original: TextBox?
        /// The top-left corner of the box in canvas space.
        let origin: Point
        /// The sort key of the box.
        let sortKey: FractionalIndex
    }

    /// The move of a box with a finger (CARD-07, D-10).
    struct Move {
        /// The box before the move.
        let box: TextBox
        /// The finger point at the start, in canvas space.
        let start: Point
        /// The box at the last finger point.
        var current: TextBox
    }

    /// The edit view. It joins the canvas view at the first edit.
    let view = TextEditView()
    /// The running edit, or `nil`.
    var edit: Edit?
    /// The running move, or `nil`.
    var move: Move?
    /// The box of the open long-press menu, or `nil`.
    var menuBox: TextBox?
    /// The menu of a long press without a drag (TOOL-08).
    var menu: UIEditMenuInteraction?
    /// The sizes of the boxes in canvas points, laid out at their first hit test.
    private var sizes: [TextBoxID: (text: String, size: Size)] = [:]
    /// Recognizes a pencil tap for the text tool (TOOL-05).
    let pencilTap = UITapGestureRecognizer()
    /// Recognizes a finger tap on a box (TOOL-06) or on a card (CARD-03, D-115).
    let fingerTap = UITapGestureRecognizer()
    /// Recognizes a finger long press on a box, for a move or the menu (CARD-07, TOOL-08).
    let longPress = UILongPressGestureRecognizer()

    /// `true` while an edit runs.
    var isEditing: Bool { edit != nil }

    /// Returns the size of a box from its layout, and keeps it until its text changes.
    func size(of box: TextBox) -> Size {
        if let known = sizes[box.id], known.text == box.text { return known.size }
        let size = TextLayout(text: box.text).size
        sizes[box.id] = (box.text, size)
        assert(size.width >= 0 && size.height > 0, "A layout has a size")
        return size
    }

    /// Returns the box under a canvas point, the newest on top, or `nil`. The tap area of a box
    /// grows to the tap target of `DesignSystem` at the zoom of the camera.
    ///
    /// - Precondition: `zoom` is positive.
    func box(
        at point: Point,
        in boxes: [TextBoxID: TextBox],
        zoom: Double,
        tapTarget: Double
    ) -> TextBox? {
        precondition(zoom > 0, "A zoom is positive, got \(zoom)")
        let reach = tapTarget / zoom
        var best: TextBox?
        for box in boxes.values {
            // A box is at most `TextStyle.maxWidth` wide, and each line but an empty last line
            // takes one UTF-16 unit at least, at most one per UTF-8 byte. Thus the origin rules
            // out most boxes before a layout: a cold tap over 10,000 stacked boxes took 125 ms
            // without the height bound (review of M5).
            let maxHeight = Double(box.text.utf8.count + 1) * TextLayout.lineHeight
            guard point.x >= box.origin.x - reach,
                point.x <= box.origin.x + TextStyle.maxWidth + reach,
                point.y >= box.origin.y - reach,
                point.y <= box.origin.y + maxHeight + reach
            else { continue }
            let size = size(of: box)
            let grow = Vector(
                dx: max(0, (reach - size.width) / 2),
                dy: max(0, (reach - size.height) / 2)
            )
            let area = Rect(
                minX: box.origin.x - grow.dx,
                minY: box.origin.y - grow.dy,
                maxX: box.origin.x + size.width + grow.dx,
                maxY: box.origin.y + size.height + grow.dy
            )
            guard area.contains(point) else { continue }
            // The ID breaks a tie of equal keys, as for the cards (data-model.md section 6). The
            // order of the dictionary changes with each launch.
            if best.map({ NodeOrder.isAbove(box, $0) }) ?? true { best = box }
        }
        return best
    }
}
