import DesignSystem
import SwiftUI
import UIKit

/// The tool palette, the squeeze of the pencil, and the current-tool button (TOOL-07, PEN-03,
/// D-63, D-64). The app plays no haptic event (PEN-06, D-23).
extension CanvasViewController: UIPencilInteractionDelegate {
    /// Connects the button, installs the one pencil interaction of the canvas, and lets a new
    /// touch set the pen width and close the palette.
    func installToolControls() {
        toolControls.select = { [weak self] tool in self?.select(tool) }
        toolControls.penWidth = penSettings.width
        toolControls.selectWidth = { [weak self] width in self?.pick(width: width) }
        toolControls.eraserSize = eraserSettings.size
        toolControls.selectEraserSize = { [weak self] size in self?.pick(eraserSize: size) }
        toolControls.openPalette = { [weak self] in self?.showPaletteUnderButton() }
        toolControls.newCard = { [weak self] in self?.showPendingCard() }
        let interaction = UIPencilInteraction(delegate: self)
        view.addInteraction(interaction)
        // PencilKit takes the pen width before `pencilBegan()` runs, so the width follows a new
        // touch at its hit test (D-131). The same touch closes the palette, and the popover lets
        // it through to the canvas (D-201).
        canvasView.onTouchHitTest = { [weak self] in
            self?.applyPenTool()
            self?.dismissPalette()
        }
        toolButtonHost.view.backgroundColor = .clear
        toolButtonHost.sizingOptions = .intrinsicContentSize
    }

    /// Picks a pen width from the palette and closes it.
    private func pick(width: PenWidth) {
        select(width: width)
        dismissPalette()
    }

    /// Picks an eraser size from the palette and closes it.
    private func pick(eraserSize: EraserSize) {
        select(eraserSize: eraserSize)
        dismissPalette()
    }

    /// Closes the palette if it is open. A share sheet or an alert stays. A close during the open
    /// animation runs after it, because UIKit drops a dismiss during a presentation (D-201).
    func dismissPalette() {
        guard let paletteHost, paletteHost === presentedViewController else { return }
        guard paletteHost.isBeingPresented, let coordinator = paletteHost.transitionCoordinator
        else {
            paletteHost.dismiss(animated: true)
            return
        }
        coordinator.animate(alongsideTransition: nil) { _ in
            paletteHost.dismiss(animated: true)
        }
    }

    /// Picks the pen width of the next stroke (TOOL-09, D-199). Every canvas of the app takes
    /// it. A stroke that runs keeps its width, because PencilKit takes the tool at the next
    /// touch (D-70).
    public func select(width: PenWidth) {
        penSettings.width = width
        toolControls.penWidth = width
        if !toolState.isPencilDown { applyPenTool() }
    }

    /// Picks the eraser size of the next erase gesture (TOOL-04, D-201). Every canvas of the app
    /// takes it. A gesture that runs keeps its size (D-70). The hover ring shows the size at once.
    public func select(eraserSize: EraserSize) {
        eraserSettings.size = eraserSize
        toolControls.eraserSize = eraserSize
        toolDidChangeForHover()
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
        // Another canvas can have picked the width or the size since this canvas took them
        // (D-199, D-201).
        toolControls.penWidth = penSettings.width
        toolControls.eraserSize = eraserSettings.size
        let host = UIHostingController(
            rootView: ToolPalette(tools: toolControls, history: historyControls)
        )
        host.view.backgroundColor = UIColor(DesignSystem.Color.chromeBackground)
        host.overrideUserInterfaceStyle = .dark
        // The Large Content Viewer needs this interaction around the buttons, and a SwiftUI
        // host adds none, as measured on the iPad (D-179).
        host.view.addInteraction(UILargeContentViewerInteraction())
        host.modalPresentationStyle = .popover
        // The row changes with the tool while the palette is open, and the popover follows it
        // (D-201).
        host.sizingOptions = .preferredContentSize
        host.preferredContentSize = host.sizeThatFits(in: view.bounds.size)
        if let popover = host.popoverPresentationController {
            popover.sourceView = source
            popover.sourceRect = rect
            popover.permittedArrowDirections = arrow
            popover.backgroundColor = UIColor(DesignSystem.Color.chromeBackground)
            // A touch on the canvas reaches the canvas, which closes the palette at the hit test
            // of the touch and then draws or erases (D-201).
            popover.passthroughViews = [canvasView]
        }
        paletteHost = host
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

    /// Gives the live canvas the pen tool of the shown zoom and the picked width, if one of them
    /// changed since the last time (architecture.md 4.2, D-131, D-199).
    func applyPenTool() {
        let zoom = cameraController.shownCamera.zoom
        let width = penSettings.width
        guard zoom != penToolZoom || width != penToolWidth else { return }
        canvasView.liveCanvas.tool = PenTool.inkingTool(width: width, zoom: zoom)
        penToolZoom = zoom
        penToolWidth = width
    }
}
