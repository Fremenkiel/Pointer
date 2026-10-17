import DesignSystem
import UIKit

/// The fallback root view controller: the black canvas background without ink. The app shows it
/// only if the device has no Metal GPU.
final class RootViewController: UIViewController {
    /// Sets the background of the root view.
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.canvasBackground
    }
}
