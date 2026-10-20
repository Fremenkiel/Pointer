import CanvasFeature
import DesignSystem
import SwiftUI
import UIKit
import WorkspaceFeature

/// The root view controller: the canvas of the current workspace, with the workspace selector
/// on top in the top left corner (WS-01).
final class AppViewController: UIViewController {
    private(set) var canvas: CanvasViewController?
    private var selector: UIViewController?
    /// The current-tool button of the shown canvas, next to the selector (D-64).
    private var toolButton: UIViewController?

    /// Sets the black background of the root view.
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.canvasBackground
    }

    /// Shows a canvas instead of the one before it.
    func show(_ newCanvas: CanvasViewController) {
        if let old = canvas {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        addChild(newCanvas)
        newCanvas.view.frame = view.bounds
        newCanvas.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(newCanvas.view, at: 0)
        newCanvas.didMove(toParent: self)
        canvas = newCanvas
        showToolButton(newCanvas.toolButton)
    }

    /// Shows the current-tool button of the canvas to the right of the selector (D-64).
    private func showToolButton(_ button: UIViewController) {
        if let old = toolButton {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        addChild(button)
        button.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button.view)
        let guide = view.safeAreaLayoutGuide
        let leading =
            selector.map {
                button.view.leadingAnchor.constraint(
                    equalTo: $0.view.trailingAnchor,
                    constant: DesignSystem.Spacing.small
                )
            }
            ?? button.view.leadingAnchor.constraint(
                equalTo: guide.leadingAnchor,
                constant: DesignSystem.Spacing.large
            )
        NSLayoutConstraint.activate([
            button.view.topAnchor.constraint(
                equalTo: guide.topAnchor,
                constant: DesignSystem.Spacing.large
            ),
            leading,
        ])
        button.didMove(toParent: self)
        toolButton = button
    }

    /// Shows the workspace selector in the top left corner.
    func showSelector(_ model: WorkspaceSelectorModel) {
        precondition(selector == nil, "The selector shows already")
        let host = UIHostingController(rootView: WorkspaceSelectorView(model: model))
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(
                equalTo: guide.topAnchor,
                constant: DesignSystem.Spacing.large
            ),
            host.view.leadingAnchor.constraint(
                equalTo: guide.leadingAnchor,
                constant: DesignSystem.Spacing.large
            ),
        ])
        host.didMove(toParent: self)
        selector = host
        if let button = toolButton {
            showToolButton(button)
        }
    }

    /// Shows a message with one button, on top of a popover that shows, for example the palette
    /// (F-12). If that popover is in a transition, the message shows after the transition. A
    /// message that comes while another one shows is dropped, because each message stays true
    /// until the user acts.
    func showMessage(_ text: String) {
        let top = topPresentedController()
        guard !(top is UIAlertController) else { return }
        let isInTransition = top.isBeingDismissed || top.isBeingPresented
        if isInTransition, let coordinator = top.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.showMessage(text)
            }
            return
        }
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: AppStrings.ok, style: .default))
        top.present(alert, animated: true)
    }

    /// The most presentations on top of each other that the app makes: a popover and an alert.
    private static let maxPresentationDepth = 4

    /// Returns the controller at the top of the presentations of this controller.
    private func topPresentedController() -> UIViewController {
        var top: UIViewController = self
        for _ in 0..<Self.maxPresentationDepth {
            if let next = top.presentedViewController { top = next }
        }
        assert(top.presentedViewController == nil, "More presentations than the app makes")
        return top
    }
}
