import Testing
import UIKit
import XCTest

@testable import BackupFeature

/// Pixel snapshots of the alert before a restore and of each message, presented in a window of
/// the test host without animations, as `CardMenuSnapshotTests` does (task 3.3 of
/// docs/m9-plan.md, TEST-07, D-114). The references can change with an iPadOS release.
///
/// It is an XCTest class, because the XCTest classes of a run run alone, before the Swift
/// Testing suites. A suite beside a presentation made the system skip it (D-114).
@MainActor
final class BackupFeatureSnapshotTests: XCTestCase {
    /// The size of the window, in points.
    private static let windowSize = CGSize(width: 600, height: 400)
    /// The time for the system to lay out and draw the alert.
    private static let settle = Duration.milliseconds(800)

    /// The alert asks before a restore and names the pre-restore snapshot.
    func testRestoreAlert() async throws {
        try await capture(RestoreAlert.controller {}, named: "backup-restore-alert")
    }

    /// Each message shows as the app shows it: the text and an OK button.
    func testMessages() async throws {
        for message in BackupMessage.allCases {
            let alert = UIAlertController(title: nil, message: message.text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            try await capture(alert, named: "backup-message-\(message)")
        }
    }

    /// Presents `alert` in a window of its own, draws it, and compares the image.
    private func capture(_ alert: UIAlertController, named name: String) async throws {
        // swiftlint:disable:next arch_05_singletons
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try XCTUnwrap(scenes.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: Self.windowSize)
        window.overrideUserInterfaceStyle = .dark
        let root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previous?.makeKey()
        }
        root.present(alert, animated: false)
        try await Task.sleep(for: Self.settle)
        let frame = alert.view.convert(alert.view.bounds, to: window).insetBy(dx: -8, dy: -8)
        let image = Self.draw(window, in: frame)
        root.dismiss(animated: false)
        // An XCTest class keeps only XCTest attachments, so a new image comes out this way.
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
        try ViewSnapshot.assertMatches(image: image, named: name)
    }

    /// Draws `rect` of the windows of the scene, the lowest window first, so that a window of
    /// the system above the window of the test shows too.
    private static func draw(_ window: UIWindow, in rect: CGRect) -> UIImage {
        let windows = (window.windowScene?.windows ?? [window]).filter { !$0.isHidden }.sorted {
            $0.windowLevel < $1.windowLevel
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = ViewSnapshot.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            for each in windows where each === window || each.windowLevel > window.windowLevel {
                let origin = CGPoint(x: each.frame.minX - rect.minX, y: each.frame.minY - rect.minY)
                each.drawHierarchy(
                    in: CGRect(origin: origin, size: each.bounds.size),
                    afterScreenUpdates: true
                )
            }
        }
    }
}
