import UIKit

/// The scene delegate. It makes the window and composes the root view controller.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    /// The window of the scene. UIKit reads this property.
    var window: UIWindow?

    /// Makes the window for a new scene and shows the root view controller.
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
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
