import DesignSystem
import UIKit

/// The layer of the hover dot above the live canvas (architecture.md 4.6, D-126). It moves
/// without a frame of the renderer and without an animation.
@MainActor
final class HoverDotLayer {
    /// The shape layer. The canvas view adds it above the live canvas.
    let layer = CAShapeLayer()
    /// `true` while the user wants the preview of the tool. The canvas reads the setting at the
    /// start of each hover (D-128).
    var isPreviewOn = true
    /// The filled dot of the pen and the text tool, around the origin of the layer.
    private let dotPath: CGPath
    /// The outline circle of the eraser, around the origin of the layer (D-133).
    private let ringPath: CGPath
    private let color = DesignSystem.Color.hoverDot.cgColor
    /// `true` while the layer holds the eraser circle.
    private var isRing = false

    /// Makes the hidden layer with the dot path. Both paths are made here, once.
    init() {
        dotPath = Self.circle(radius: DesignSystem.Size.hoverDotRadius)
        ringPath = Self.circle(radius: CGFloat(EraserTool.radius))
        layer.bounds = .zero
        layer.path = dotPath
        layer.fillColor = color
        layer.strokeColor = nil
        layer.lineWidth = DesignSystem.Size.hoverRingWidth
        layer.isHidden = true
        // A move must not animate, so the implicit actions of the changed keys are off (D-126).
        layer.actions = [
            "position": NSNull(), "path": NSNull(), "hidden": NSNull(), "fillColor": NSNull(),
            "strokeColor": NSNull(), "contentsScale": NSNull(),
        ]
    }

    /// The center of the shown mark, or `nil` while the layer is hidden.
    var shownCenter: CGPoint? { layer.isHidden ? nil : layer.position }

    // Only the tests read it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// `true` while the layer holds the outline circle of the eraser.
    var showsRing: Bool { isRing }
    // swiftlint:enable unused_declaration

    /// Shows `mark` at its center, or hides the layer for `nil`. The path changes only when the
    /// shape changes, at a tool change. A move allocates nothing in Pointer code (PERF-01).
    func show(_ mark: HoverDot?) {
        guard let mark else {
            layer.isHidden = true
            return
        }
        if mark.isRing != isRing {
            isRing = mark.isRing
            layer.path = isRing ? ringPath : dotPath
            layer.fillColor = isRing ? nil : color
            layer.strokeColor = isRing ? color : nil
        }
        layer.position = mark.center
        layer.isHidden = false
    }

    /// A circle of `radius` around the origin.
    private static func circle(radius: CGFloat) -> CGPath {
        CGPath(
            ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
            transform: nil
        )
    }
}
