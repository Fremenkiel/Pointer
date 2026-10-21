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
    /// The up button inside a card, next to the tool button (CARD-04), or `nil` on the root
    /// canvas.
    private(set) var upButton: UIViewController?

    /// Sets the canvas color as the background of the root view (D-106).
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

    /// Shows a new canvas above the shown one, at opacity 0, so that its first frame draws while
    /// the open of a card ends (D-98). `completeSwap(to:)` makes it the canvas.
    func showAbove(_ newCanvas: CanvasViewController) {
        precondition(newCanvas !== canvas, "A new canvas")
        addChild(newCanvas)
        newCanvas.view.frame = view.bounds
        newCanvas.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        newCanvas.view.alpha = 0
        let index = canvas.map { view.subviews.firstIndex(of: $0.view) ?? 0 } ?? 0
        view.insertSubview(newCanvas.view, at: index + 1)
        newCanvas.didMove(toParent: self)
    }

    /// Removes a canvas that `showAbove(_:)` added, after a failed open.
    func removeAbove(_ newCanvas: CanvasViewController) {
        precondition(newCanvas !== canvas, "Only a canvas above the shown one goes")
        newCanvas.willMove(toParent: nil)
        newCanvas.view.removeFromSuperview()
        newCanvas.removeFromParent()
    }

    /// Fades the canvas that `showAbove(_:)` added in over `duration` seconds, then removes the
    /// old canvas and shows the chrome of the new one (D-98).
    func completeSwap(
        to newCanvas: CanvasViewController,
        duration: TimeInterval,
        completion: @escaping @MainActor () -> Void
    ) {
        let old = canvas
        UIView.animate(
            withDuration: duration,
            animations: { newCanvas.view.alpha = 1 },
            completion: { [weak self] _ in
                MainActor.assumeIsolated {
                    if let old {
                        old.willMove(toParent: nil)
                        old.view.removeFromSuperview()
                        old.removeFromParent()
                    }
                    self?.canvas = newCanvas
                    self?.showToolButton(newCanvas.toolButton)
                    completion()
                }
            }
        )
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

    /// Shows the up button to the right of the tool button, or removes it for `nil` (CARD-04,
    /// architecture.md 6.4).
    func showUpButton(_ action: (() -> Void)?) {
        if let old = upButton {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
            upButton = nil
        }
        guard let action, let toolButton else { return }
        let host = UIHostingController(rootView: UpButton(action: action))
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: toolButton.view.topAnchor),
            host.view.leadingAnchor.constraint(
                equalTo: toolButton.view.trailingAnchor,
                constant: DesignSystem.Spacing.small
            ),
        ])
        host.didMove(toParent: self)
        upButton = host
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
