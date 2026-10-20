import Testing
import UIKit

@testable import Pointer

/// The messages of the app reach the user also while a popover shows (F-12 of
/// docs/m4-fix-plan.md, storage.md section 9).
@MainActor
@Suite("App messages")
struct AppMessageTests {
    /// The longest wait for a presentation to end.
    private static let timeout = Duration.seconds(3)

    @Test("A message shows while the palette is open")
    func messageOverPalette() async throws {
        let app = try #require(try OnScreenCanvas.host() as? AppViewController)
        let palette = UIViewController()
        palette.modalPresentationStyle = .popover
        palette.popoverPresentationController?.sourceView = app.view
        app.present(palette, animated: false)
        defer { app.dismiss(animated: false) }
        try await Self.waitForPresentations(of: app)
        app.showMessage(AppStrings.rowsSkipped)
        try await Self.waitForPresentations(of: palette)
        let alert = palette.presentedViewController as? UIAlertController
        #expect(alert?.message == AppStrings.rowsSkipped)
    }

    /// Waits until no presentation of `controller` is in a transition.
    private static func waitForPresentations(of controller: UIViewController) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while controller.presentedViewController?.isBeingPresented == true, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
