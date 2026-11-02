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
    /// The outline circles of the eraser, one per size, around the origin of the layer (D-133,
    /// D-201).
    private let ringPaths: [(radius: CGFloat, path: CGPath)]
    private let color = DesignSystem.Color.hoverDot.cgColor
    /// `true` while the layer holds an eraser circle.
    private var isRing = false
    /// The radius of the eraser circle that the layer holds, or 0 for the dot.
    private var ringRadius: CGFloat = 0

    /// Makes the hidden layer with the dot path. All paths are made here, once.
    init() {
        dotPath = Self.circle(radius: DesignSystem.Size.hoverDotRadius)
        ringPaths = EraserSize.allCases.map { size in
            let radius = CGFloat(size.viewPoints)
            return (radius: radius, path: Self.circle(radius: radius))
        }
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

    // Only the tests read them (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// `true` while the layer holds the outline circle of the eraser.
    var showsRing: Bool { isRing }
    /// The radius of the outline circle that the layer holds, or 0 for the dot.
    var shownRingRadius: CGFloat { ringRadius }
    // swiftlint:enable unused_declaration

    /// Shows `mark` at its center, or hides the layer for `nil`. The path changes only when the
    /// shape changes, at a tool change or an eraser size change. A move allocates nothing in
    /// Pointer code (PERF-01).
    func show(_ mark: HoverDot?) {
        guard let mark else {
            layer.isHidden = true
            return
        }
        if mark.isRing != isRing || (mark.isRing && mark.radius != ringRadius) {
            isRing = mark.isRing
            ringRadius = isRing ? mark.radius : 0
            layer.path = isRing ? ringPath(radius: mark.radius) : dotPath
            layer.fillColor = isRing ? nil : color
            layer.strokeColor = isRing ? color : nil
        }
        layer.position = mark.center
        layer.isHidden = false
    }

    /// The ring path of `radius`. A radius of no eraser size gives the first ring.
    private func ringPath(radius: CGFloat) -> CGPath {
        ringPaths.first { $0.radius == radius }?.path ?? ringPaths[0].path
    }

    /// A circle of `radius` around the origin.
    private static func circle(radius: CGFloat) -> CGPath {
        CGPath(
            ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
            transform: nil
        )
    }
}
