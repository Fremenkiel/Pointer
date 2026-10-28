import Testing
import UIKit

@testable import Pointer

/// The messages of the app reach the user also while a popover shows (F-12 of
/// the M4 fix plan, storage.md section 9).
@MainActor
@Suite("App messages")
struct AppMessageTests {
    /// The longest wait for a presentation or a dismissal to end.
    private static let timeout = Duration.seconds(3)

    @Test("A message shows while the palette is open")
    func messageOverPalette() async throws {
        let window = try Self.makeWindow()
        defer { window.isHidden = true }
        let app = try #require(window.rootViewController as? AppViewController)
        let palette = UIViewController()
        palette.modalPresentationStyle = .popover
        palette.popoverPresentationController?.sourceView = app.view
        app.present(palette, animated: false)
        try await Self.waitForTransitions(of: app)
        app.showMessage(AppStrings.rowsSkipped)
        try await Self.waitForTransitions(of: palette)
        let alert = palette.presentedViewController as? UIAlertController
        #expect(alert?.message == AppStrings.rowsSkipped)
        app.dismiss(animated: false)
        try await Self.waitForTransitions(of: app)
        #expect(app.presentedViewController == nil, "The test leaves no presentation")
    }

    /// Makes a visible window of its own with an app screen, in the scene of the test host. Other
    /// suites run at the same time and present on the window of the host, so the test does not
    /// share it (TEST-04). The window does not become the key window, which other tests use.
    private static func makeWindow() throws -> UIWindow {
        let scene = try #require(try OnScreenCanvas.host().view.window?.windowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = AppViewController()
        window.isHidden = false
        return window
    }

    /// Waits until no presentation or dismissal of `controller` or above it is in progress.
    /// UIKit gives a transition coordinator while one runs (`transitionCoordinator`).
    private static func waitForTransitions(of controller: UIViewController) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline, isInTransition(controller) {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func isInTransition(_ controller: UIViewController) -> Bool {
        var node: UIViewController? = controller
        for _ in 0..<4 {
            guard let current = node else { return false }
            if current.transitionCoordinator != nil { return true }
            node = current.presentedViewController
        }
        return false
    }
}
