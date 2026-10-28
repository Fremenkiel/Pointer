import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit
import XCTest

@testable import CanvasFeature

/// Pixel snapshots of the card menu and the rename alert, presented in a window of the test host
/// without animations (D-114, TEST-07). The content tests of `CardMenuTests` stay. The reference
/// images can change with an iPadOS release.
///
/// It is an XCTest class, because the XCTest classes of a run run alone, before the Swift
/// Testing suites, which run at the same time. In a full run, a suite beside it made the system
/// skip the menu, and all three presentations captured a black image.
@MainActor
final class CardMenuSnapshotTests: XCTestCase {
    /// The size of the window, in points.
    private static let windowSize = CGSize(width: 600, height: 400)
    /// The time for the system to lay out and draw the menu or the alert.
    private static let settle = Duration.milliseconds(800)

    /// A window on the scene of the test host with a black root view.
    private static func makeWindow() throws -> UIWindow {
        // Only UIApplication reaches the scene of the test host, as in `ViewSnapshot` (D-59).
        // swiftlint:disable:next arch_05_singletons
        let scenes = UIApplication.shared.connectedScenes
        let scene = try XCTUnwrap(scenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: windowSize)
        window.overrideUserInterfaceStyle = .dark
        let root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        // The system shows an edit menu only in the key window.
        window.makeKeyAndVisible()
        return window
    }

    /// Hides the window of a test and gives the key back to the window of the test host.
    private static func close(_ window: UIWindow, previous: UIWindow?) {
        window.isHidden = true
        previous?.makeKey()
    }

    /// The key window of the scene of the test host before a test.
    private static func keyWindow() -> UIWindow? {
        // swiftlint:disable:next arch_05_singletons
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow
    }

    /// A canvas screen with one card titled "Tree", with the card of its menu.
    private static func makeController() throws -> (CanvasViewController, Card) {
        let frame = Rect(origin: Point(x: -50, y: -40), size: Size(width: 100, height: 80))
        let card = try NewCardTests.card(1, frame: frame).retitling(
            "Tree",
            at: Fixtures.clock().now()
        )
        var content = CanvasContent(canvasID: Fixtures.canvas)
        try content.add(card)
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.camera = Camera(center: .zero, zoom: 1)
        dependencies.repository = RecordingLibrary()
        return (CanvasViewController(dependencies: dependencies), card)
    }

    /// Draws `rect` of the windows of the scene, the lowest window first, so that a menu in a
    /// window of the system shows on top of the window of the test. After a heavy test of a full
    /// run, the render server gave no snapshot for a few seconds, and the image was black, so
    /// the draw runs again until each window gives its snapshot (review of 2026-10-28, the M11
    /// plan phase 1).
    private static func capture(_ window: UIWindow, in rect: CGRect) async throws -> UIImage {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.drawTimeout)
        // The deadline bounds the loop (FLOW-03).
        while clock.now < deadline {
            if let image = try draw(window, in: rect) { return image }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SnapshotDrawError.noSnapshot
    }

    /// The longest wait for the snapshots of the windows.
    private static let drawTimeout = Duration.seconds(5)

    /// Draws `rect` of the windows once, or returns `nil` if a window gave no snapshot.
    private static func draw(_ window: UIWindow, in rect: CGRect) throws -> UIImage? {
        let scene = try XCTUnwrap(window.windowScene)
        let windows = scene.windows.filter { !$0.isHidden }.sorted {
            $0.windowLevel < $1.windowLevel
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = ViewSnapshot.scale
        format.opaque = true
        var isComplete = true
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            for each in windows where each === window || each.windowLevel > window.windowLevel {
                let drawn = each.drawHierarchy(
                    in: CGRect(
                        origin: CGPoint(
                            x: each.frame.minX - rect.minX,
                            y: each.frame.minY - rect.minY
                        ),
                        size: each.bounds.size
                    ),
                    afterScreenUpdates: true
                )
                isComplete = isComplete && drawn
            }
        }
        return isComplete ? image : nil
    }

    /// The card menu shows Rename and Delete in the style of the system.
    func testMenu() async throws {
        let previous = Self.keyWindow()
        let window = try Self.makeWindow()
        defer { Self.close(window, previous: previous) }
        let (controller, card) = try Self.makeController()
        let root = try XCTUnwrap(window.rootViewController)
        let anchor = UIView(frame: root.view.bounds)
        root.view.addSubview(anchor)
        let interaction = UIEditMenuInteraction(delegate: controller)
        anchor.addInteraction(interaction)
        controller.cardInteraction.menuCard = card
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        let region = CGRect(x: 100, y: 100, width: 400, height: 200)
        var image = UIImage()
        // The system can skip a menu while the window becomes key, so the test asks again.
        for _ in 0..<Self.menuAttempts {
            interaction.presentEditMenu(
                with: UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: 300, y: 200))
            )
            try await Task.sleep(for: Self.settle)
            image = try await Self.capture(window, in: region)
            interaction.dismissMenu()
            if try !Self.isBlack(image) { break }
            try await Task.sleep(for: Self.settle)
        }
        XCTAssertFalse(
            try Self.isBlack(image),
            "A black capture: \(Self.state(of: root, window: window, frame: region))"
        )
        try ViewSnapshot.assertMatches(image: image, named: "card-menu")
    }

    /// The presentations of the menu before the test compares what it has.
    private static let menuAttempts = 3

    /// `true` if each pixel of the image is black, so no menu shows.
    private static func isBlack(_ image: UIImage) throws -> Bool {
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        return !data.contains { $0 > 16 && $0 < 255 }
    }

    /// The rename alert shows the title in a text field with Cancel and Rename.
    func testRenameAlert() async throws {
        let previous = Self.keyWindow()
        let window = try Self.makeWindow()
        defer { Self.close(window, previous: previous) }
        let (controller, card) = try Self.makeController()
        let root = try XCTUnwrap(window.rootViewController)
        let alert = controller.renameAlert(for: card.id)
        root.present(alert, animated: false)
        try await Task.sleep(for: Self.settle)
        // The caret blinks, so the field gives up the focus before the capture.
        alert.textFields?.first?.resignFirstResponder()
        try await Task.sleep(for: Self.settle)
        let frame = alert.view.convert(alert.view.bounds, to: window)
        let image = try await Self.capture(window, in: frame.insetBy(dx: -8, dy: -8))
        XCTAssertFalse(
            try Self.isBlack(image),
            "A black capture: \(Self.state(of: alert, window: window, frame: frame))"
        )
        root.dismiss(animated: false)
        try ViewSnapshot.assertMatches(image: image, named: "card-rename-alert")
    }

    /// The message at the stroke limit shows as the app shows each message: the text and an OK
    /// button (D-181, the M10 plan task 6.2).
    func testStrokeLimitMessage() async throws {
        let previous = Self.keyWindow()
        let window = try Self.makeWindow()
        defer { Self.close(window, previous: previous) }
        let root = try XCTUnwrap(window.rootViewController)
        let alert = UIAlertController(
            title: nil,
            message: CanvasStrings.strokeLimit,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        root.present(alert, animated: false)
        try await Task.sleep(for: Self.settle)
        let frame = alert.view.convert(alert.view.bounds, to: window)
        let image = try await Self.capture(window, in: frame.insetBy(dx: -8, dy: -8))
        XCTAssertFalse(
            try Self.isBlack(image),
            "A black capture: \(Self.state(of: alert, window: window, frame: frame))"
        )
        root.dismiss(animated: false)
        // An XCTest class keeps only XCTest attachments, so a new image comes out this way.
        let attachment = XCTAttachment(image: image)
        attachment.name = "canvas-message-stroke-limit"
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
        try ViewSnapshot.assertMatches(image: image, named: "canvas-message-stroke-limit")
    }
}

extension CardMenuSnapshotTests {
    /// The state of a black capture, as `BackupFeatureSnapshotTests.state` names it.
    fileprivate static func state(
        of presented: UIViewController,
        window: UIWindow,
        frame: CGRect
    ) -> String {
        BackupFeatureSnapshotTests.state(of: presented, window: window, frame: frame)
    }
}
