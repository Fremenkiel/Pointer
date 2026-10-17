import UIKit

/// The application delegate. It only names the scene configuration, because the scene owns the UI.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Returns the configuration for a new scene session.
    ///
    /// - Returns: The default configuration from `Info.plist`.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
}
