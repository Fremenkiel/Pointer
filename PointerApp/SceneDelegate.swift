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
        let container = AppViewController()
        window.rootViewController = container
        window.makeKeyAndVisible()
        self.window = window
        let composition = AppComposition(
            window: window,
            container: container,
            defaults: .standard
        )
        self.composition = composition
        Task { await composition.start() }
    }

    /// Starts the check for an idle moment for the daily snapshot.
    func sceneDidBecomeActive(_ scene: UIScene) {
        composition?.startIdleTimer()
    }

    /// Stops the check for an idle moment.
    func sceneWillResignActive(_ scene: UIScene) {
        composition?.stopIdleTimer()
    }

    /// Writes all pending rows and the device state (storage.md section 4).
    func sceneDidEnterBackground(_ scene: UIScene) {
        composition?.enterBackground()
    }
}
