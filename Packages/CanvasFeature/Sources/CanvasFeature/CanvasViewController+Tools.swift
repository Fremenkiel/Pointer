import DesignSystem
import SwiftUI
import UIKit

/// The tool palette, the squeeze of the pencil, and the current-tool button (TOOL-07, PEN-03,
/// D-63, D-64). The app plays no haptic event (PEN-06, D-23).
extension CanvasViewController: UIPencilInteractionDelegate {
    /// Connects the button, installs the one pencil interaction of the canvas, and lets a new
    /// touch set the pen width.
    func installToolControls() {
        toolControls.select = { [weak self] tool in self?.pick(tool) }
        toolControls.openPalette = { [weak self] in self?.showPaletteUnderButton() }
        toolControls.newCard = { [weak self] in self?.showPendingCard() }
        let interaction = UIPencilInteraction(delegate: self)
        view.addInteraction(interaction)
        // PencilKit takes the pen width before `pencilBegan()` runs, so the width follows a new
        // touch at its hit test (D-131).
        canvasView.onTouchHitTest = { [weak self] in self?.applyPenTool() }
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
        // The Large Content Viewer needs this interaction around the buttons, and a SwiftUI
        // host adds none, as measured on the iPad (D-179).
        host.view.addInteraction(UILargeContentViewerInteraction())
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
        self.squeeze(
            isEnded: squeeze.phase == .ended,
            action: UIPencilInteraction.preferredSqueezeAction,
            hoverLocation: squeeze.hoverPose?.location
        )
    }

    /// Opens the palette for a squeeze with the setting `action` at the anchor of
    /// `PaletteAnchor`, or does nothing (D-63). During a card flight it does nothing.
    func squeeze(isEnded: Bool, action: UIPencilPreferredAction, hoverLocation: CGPoint?) {
        guard takesPencilActions else { return }
        let anchor = PaletteAnchor.squeeze(
            isEnded: isEnded,
            action: action,
            hoverLocation: hoverLocation,
            lastPencilLocation: lastPencilLocation
        )
        guard let anchor else { return }
        showPalette(at: anchor)
    }

    /// A double tap switches between pen and eraser for the settings of D-130 (architecture.md
    /// 4.5). The setting is read at each tap, because the user can change it while the app runs.
    public func pencilInteraction(
        _ interaction: UIPencilInteraction,
        didReceiveTap tap: UIPencilInteraction.Tap
    ) {
        doubleTap(action: UIPencilInteraction.preferredTapAction)
    }

    /// Picks the tool of a double tap with the setting `action`, or does nothing (D-130). A tap
    /// during a pencil touch takes effect at the next pencil down (D-70), and a tap during a text
    /// edit ends the edit (D-87). During a card flight it does nothing.
    func doubleTap(action: UIPencilPreferredAction) {
        guard takesPencilActions else { return }
        guard let next = ToolSwitch.tool(after: tool, action: action) else { return }
        select(next)
    }

    /// `true` if a double tap and a squeeze act: the container shows this canvas, and no card
    /// flight runs on it (architecture.md 4.5, CARD-03, CARD-04).
    var takesPencilActions: Bool { isShownCanvas && !isInCardTransition }

    /// Gives the live canvas the pen width of the shown zoom, if the zoom changed since the last
    /// time (architecture.md 4.2).
    func applyPenTool() {
        let zoom = cameraController.shownCamera.zoom
        guard zoom != penToolZoom else { return }
        canvasView.liveCanvas.tool = PenTool.inkingTool(zoom: zoom)
        penToolZoom = zoom
    }
}
