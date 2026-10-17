import UIKit

/// PointerApp can read Apple singletons and pass them down (ARCH-05).
@MainActor final class Composition {
    /// The application and the file manager.
    let parts = (UIApplication.shared, FileManager.default, Bundle.main)
}
