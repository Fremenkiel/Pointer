import Geometry
import Model
import Rendering
import UIKit

/// The edit view of a text box: a `UITextView` (TextKit 2) at the place of the box
/// (architecture.md sections 5.4 and 7). Scribble, the keyboard, and dictation come with it.
///
/// It uses the font, the line height, and the wrap width of `TextLayout` at the zoom of the
/// camera, without a scale transform (D-85). Only a pinch scales it, until the pinch ends.
@MainActor
final class TextEditView: UITextView {
    /// The zoom of the last layout, or `nil` before the first layout of a text.
    private(set) var layoutZoom: Double?
    /// The part of the view that takes touches: the text box with a margin. Outside it, a tap
    /// reaches the canvas and ends the edit.
    private var touchArea = CGRect.zero

    /// Makes an empty edit view.
    init() {
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        textColor = .white
        tintColor = .white
        overrideUserInterfaceStyle = .dark
        keyboardAppearance = .dark
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        isScrollEnabled = false
        allowsEditingTextAttributes = false
        dataDetectorTypes = []
        // The notes hold code, so the text stays as typed.
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no
        assert(textLayoutManager != nil, "The edit view uses TextKit 2")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // swiftlint:disable:next safe_07_fatal_error
        fatalError("TextEditView has no coder support")
    }

    /// The attributes of the text at a zoom: SF Mono at 17 points times the zoom, white, with
    /// the fixed line height of `TextLayout` (D-15, D-85).
    static func attributes(zoom: Double) -> [NSAttributedString.Key: Any] {
        precondition(zoom > 0, "A zoom is positive, got \(zoom)")
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = TextLayout.lineHeight * zoom
        style.maximumLineHeight = TextLayout.lineHeight * zoom
        style.lineBreakMode = .byWordWrapping
        return [
            .font: TextLayout.font(size: TextStyle.fontSize * zoom),
            .foregroundColor: UIColor.white,
            .paragraphStyle: style,
        ]
    }

    /// Lays out the view for a box at `origin` with the camera: the font of the zoom, the wrap
    /// width of `TextStyle.maxWidth`, and the height of the lines.
    ///
    /// - Precondition: The view size is positive.
    func layOut(origin: Point, camera: Camera, viewSize: Size) {
        precondition(viewSize.width > 0 && viewSize.height > 0, "The view has a size")
        if camera.zoom != layoutZoom {
            let attributes = Self.attributes(zoom: camera.zoom)
            layoutZoom = camera.zoom
            typingAttributes = attributes
            let range = NSRange(location: 0, length: textStorage.length)
            textStorage.setAttributes(attributes, range: range)
        }
        transform = .identity
        let corner = camera.viewPoint(fromCanvas: origin, viewSize: viewSize)
        let layout = TextLayout(text: text ?? "")
        frame = CGRect(
            x: corner.x,
            y: corner.y,
            width: TextStyle.maxWidth * camera.zoom,
            height: layout.size.height * camera.zoom
        )
        let caret = TextLayout.lineHeight * camera.zoom
        touchArea = CGRect(
            x: 0,
            y: 0,
            width: layout.size.width * camera.zoom + caret,
            height: layout.size.height * camera.zoom
        ).insetBy(dx: -caret / 2, dy: -caret / 2)
        assert(frame.origin.x.isFinite && frame.origin.y.isFinite, "The edit view has a place")
    }

    /// Sets a new text. The next layout gives it the style of the zoom.
    func setText(_ newText: String) {
        text = newText
        layoutZoom = nil
        assert(layoutZoom == nil, "A new text gets the style at the next layout")
    }

    /// Follows the camera during a pinch with a scale transform of the last layout (D-85).
    func follow(origin: Point, camera: Camera, viewSize: Size) {
        precondition(camera.zoom > 0, "A zoom is positive, got \(camera.zoom)")
        guard let layoutZoom else {
            layOut(origin: origin, camera: camera, viewSize: viewSize)
            return
        }
        let corner = camera.viewPoint(fromCanvas: origin, viewSize: viewSize)
        let scale = camera.zoom / layoutZoom
        transform = .identity
        frame.origin = CGPoint(x: corner.x, y: corner.y)
        // The transform scales about the center, so the shift keeps the top-left corner.
        let shift = CGPoint(x: frame.width * (scale - 1) / 2, y: frame.height * (scale - 1) / 2)
        transform = CGAffineTransform(translationX: shift.x, y: shift.y)
            .scaledBy(x: scale, y: scale)
    }

    /// Takes only the touches on the text box, so that a tap beside it reaches the canvas.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        touchArea.contains(point)
    }
}
