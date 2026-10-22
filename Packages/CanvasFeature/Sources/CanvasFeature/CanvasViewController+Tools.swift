import DesignSystem
import SwiftUI
import UIKit

/// The tool palette, the squeeze of the pencil, and the current-tool button (TOOL-07, PEN-03,
/// D-63, D-64). The app plays no haptic event (PEN-06, D-23).
extension CanvasViewController: UIPencilInteractionDelegate {
    /// Connects the button and installs the one pencil interaction of the canvas.
    func installToolControls() {
        toolControls.select = { [weak self] tool in self?.pick(tool) }
        toolControls.openPalette = { [weak self] in self?.showPaletteUnderButton() }
        toolControls.newCard = { [weak self] in self?.showPendingCard() }
        let interaction = UIPencilInteraction(delegate: self)
        view.addInteraction(interaction)
        toolButtonHost.view.backgroundColor = .clear
        toolButtonHost.sizingOptions = .intrinsicContentSize
    }

    /// Picks a tool from the palette and closes it.
    private func pick(_ tool: Tool) {
        select(tool)
        presentedViewController?.dismiss(animated: true)
    }

    /// Opens the palette under the current-tool button (D-64). The button is the first square
    /// of the chrome, left of the card button.
    private func showPaletteUnderButton() {
        let source = toolButtonHost.viewIfLoaded ?? view
        let bounds = source?.bounds ?? .zero
        let button = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: min(bounds.width, DesignSystem.Size.tapTarget),
            height: bounds.height
        )
        showPalette(from: source, rect: button, arrow: .up)
    }

    /// Opens the palette at a point of the canvas, for a squeeze (D-63).
    func showPalette(at point: CGPoint) {
        showPalette(
            from: view,
            rect: CGRect(origin: point, size: .zero),
            arrow: .any
        )
    }

    private func showPalette(
        from source: UIView?,
        rect: CGRect,
        arrow: UIPopoverArrowDirection
    ) {
        guard presentedViewController == nil, let source else { return }
        let host = UIHostingController(
            rootView: ToolPalette(tools: toolControls, history: historyControls)
        )
        host.view.backgroundColor = UIColor(DesignSystem.Color.chromeBackground)
        host.overrideUserInterfaceStyle = .dark
        host.modalPresentationStyle = .popover
        host.preferredContentSize = host.sizeThatFits(in: view.bounds.size)
        if let popover = host.popoverPresentationController {
            popover.sourceView = source
            popover.sourceRect = rect
            popover.permittedArrowDirections = arrow
            popover.backgroundColor = UIColor(DesignSystem.Color.chromeBackground)
        }
        present(host, animated: true)
    }

    /// A squeeze opens the palette at the pencil tip (architecture.md 4.5).
    public func pencilInteraction(
        _ interaction: UIPencilInteraction,
        didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
    ) {
        let anchor = PaletteAnchor.squeeze(
            isEnded: squeeze.phase == .ended,
            action: UIPencilInteraction.preferredSqueezeAction,
            hoverLocation: squeeze.hoverPose?.location,
            lastPencilLocation: lastPencilLocation
        )
        guard let anchor else { return }
        showPalette(at: anchor)
    }
}
