import UIKit

/// The scene delegate. It makes the window, composes the root view controller, and passes the
/// changes of the scene state to the composition.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    /// The window of the scene. UIKit reads this property.
    var window: UIWindow?
    private var composition: AppComposition?

    /// Makes the window for a new scene, shows the root view in the canvas color, and opens the
    /// library.
    ///
    /// - Precondition: `scene` is a `UIWindowScene`.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            preconditionFailure("Scene \(session.persistentIdentifier) is not a UIWindowScene")
        }
        let window = InputTrackingWindow(windowScene: windowScene)
        self.window = window
        startComposition(in: window, after: nil)
        window.makeKeyAndVisible()
    }

    /// Makes a composition with a new root view and starts it. After a restore, the new
    /// composition replaces the old one and opens the files again, as at launch (D-148).
    private func startComposition(
        in window: InputTrackingWindow,
        after handoff: AppComposition.Handoff?
    ) {
        let container = AppViewController()
        window.rootViewController = container
        let composition = AppComposition(
            window: window,
            container: container,
            defaults: .standard
        )
        composition.onReplace = { [weak self, weak window] handoff in
            guard let self, let window else { return }
            startComposition(in: window, after: handoff)
        }
        self.composition = composition
        Task {
            await composition.start(after: handoff)
            // At launch, the scene becomes active after the start and starts the timer.
            if handoff != nil, UIApplication.shared.applicationState == .active {
                composition.startIdleTimer()
            }
        }
    }

    /// Starts the check for an idle moment for the daily snapshot.
    func sceneDidBecomeActive(_ scene: UIScene) {
        composition?.startIdleTimer()
    }

    /// Stops the check for an idle moment and writes the preview of a child canvas.
    func sceneWillResignActive(_ scene: UIScene) {
        composition?.resignActive()
    }

    /// Writes all pending rows and the device state (storage.md section 4).
    func sceneDidEnterBackground(_ scene: UIScene) {
        composition?.enterBackground()
    }
}
