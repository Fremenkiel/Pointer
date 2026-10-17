import DesignSystem
import UIKit

/// The root view controller. In M0 it shows the empty black canvas background.
final class RootViewController: UIViewController {
    /// Sets the background of the root view.
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.canvasBackground
    }
}
