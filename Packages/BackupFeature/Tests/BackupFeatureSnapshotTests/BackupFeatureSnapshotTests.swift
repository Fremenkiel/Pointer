import Testing
import UIKit
import XCTest

@testable import BackupFeature

/// Pixel snapshots of the alert before a restore and of each message, presented in a window of
/// the test host without animations, as `CardMenuSnapshotTests` does (task 3.3 of
/// the M9 plan, TEST-07, D-114). The references can change with an iPadOS release.
///
/// It is an XCTest class, because the XCTest classes of a run run alone, before the Swift
/// Testing suites. A suite beside a presentation made the system skip it (D-114).
@MainActor
final class BackupFeatureSnapshotTests: XCTestCase {
    /// The size of the window, in points.
    private static let windowSize = CGSize(width: 600, height: 400)
    /// The time for the system to lay out and draw the alert.
    private static let settle = Duration.milliseconds(800)
    /// The longest wait for the end of a presentation.
    private static let presentationTimeout = Duration.seconds(5)

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
        // An alert fades in also without an animation. Under the load of a full run the fade
        // took longer than 0.8 s, so the capture waits until the presentation ends.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.presentationTimeout)
        while Self.isPresenting(alert, from: root), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: Self.settle)
        let frame = alert.view.convert(alert.view.bounds, to: window).insetBy(dx: -8, dy: -8)
        let image = try await Self.drawWhenReady(window, in: frame)
        XCTAssertFalse(
            try Self.isBlack(image),
            "A black capture: \(Self.state(of: alert, window: window, frame: frame))"
        )
        root.dismiss(animated: false)
        // An XCTest class keeps only XCTest attachments, so a new image comes out this way.
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
        try ViewSnapshot.assertMatches(image: image, named: name)
    }

    /// `true` if each pixel of the image is black, so the window drew nothing.
    static func isBlack(_ image: UIImage) throws -> Bool {
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        return !data.contains { $0 > 16 && $0 < 255 }
    }

    /// The state of the presentation and the windows, for the message of a black capture. In
    /// 5 of 9 full runs on 2026-10-28, also on the code of the review, the draw of a presented
    /// alert or menu gave a black image for a few seconds early in the run, and the cause is
    /// open. The message names the state of that moment.
    static func state(of presented: UIViewController, window: UIWindow, frame: CGRect) -> String {
        let scene = window.windowScene
        let windows = (scene?.windows ?? []).map {
            "\(type(of: $0)) level \($0.windowLevel.rawValue) hidden \($0.isHidden)"
                + " key \($0.isKeyWindow) frame \($0.frame)"
        }
        // swiftlint:disable:next arch_05_singletons
        let app = UIApplication.shared.applicationState.rawValue
        let presentedWindow: String
        if let presentedIn = presented.view.window {
            presentedWindow = presentedIn === window ? "the test window" : "another window"
        } else {
            presentedWindow = "no window"
        }
        return "app state \(app), scene \(String(describing: scene?.activationState.rawValue)),"
            + " presented in \(presentedWindow), frame \(frame), windows \(windows)"
    }

    /// True while the presentation of `alert` from `root` runs.
    private static func isPresenting(
        _ alert: UIAlertController,
        from root: UIViewController
    ) -> Bool {
        alert.isBeingPresented || alert.view.window == nil || root.transitionCoordinator != nil
    }

    /// Draws `rect` of the windows of the scene as `draw` does, again until each draw succeeds.
    /// After a heavy test of a full run, the render server gave no snapshot for a few seconds,
    /// and the image was black (review of 2026-10-28, the M11 plan phase 1).
    ///
    /// - Throws: If no draw succeeds within `presentationTimeout`.
    static func drawWhenReady(_ window: UIWindow, in rect: CGRect) async throws -> UIImage {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: presentationTimeout)
        // The deadline bounds the loop (FLOW-03).
        while clock.now < deadline {
            if let image = draw(window, in: rect) { return image }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SnapshotDrawError.noSnapshot
    }

    /// Draws `rect` of the windows of the scene, the lowest window first, so that a window of
    /// the system above the window of the test shows too.
    ///
    /// - Returns: The image, or `nil` if a window gave no snapshot.
    private static func draw(_ window: UIWindow, in rect: CGRect) -> UIImage? {
        let windows = (window.windowScene?.windows ?? [window]).filter { !$0.isHidden }.sorted {
            $0.windowLevel < $1.windowLevel
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = ViewSnapshot.scale
        format.opaque = true
        var isComplete = true
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            for each in windows where each === window || each.windowLevel > window.windowLevel {
                let origin = CGPoint(x: each.frame.minX - rect.minX, y: each.frame.minY - rect.minY)
                let drawn = each.drawHierarchy(
                    in: CGRect(origin: origin, size: each.bounds.size),
                    afterScreenUpdates: true
                )
                isComplete = isComplete && drawn
            }
        }
        return isComplete ? image : nil
    }
}

/// The render server gave no snapshot of a window within the timeout.
enum SnapshotDrawError: Error {
    case noSnapshot
}
