import Foundation
import Testing
import UIKit

@testable import Pointer

/// The canvas of the app has the color of CAN-01 (D-106).
@MainActor
@Suite("Canvas color")
struct CanvasColorTests {
    /// RGB(41, 44, 51) of CAN-01.
    private static let expected = [41, 44, 51]

    @Test("The renderer of the app and the root view use RGB(41, 44, 51)")
    func canvasColor() throws {
        let defaults = try #require(UserDefaults(suiteName: "CanvasColorTests-\(UUID())"))
        let background = CanvasComposition.rendererConfiguration(defaults).background
        let channels = [background.x, background.y, background.z]
        #expect(channels.map { Int(($0 * 255).rounded()) } == Self.expected)
        let root = AppViewController()
        root.loadViewIfNeeded()
        let color = try #require(root.view.backgroundColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect([red, green, blue].map { Int(($0 * 255).rounded()) } == Self.expected)
        #expect(alpha == 1)
    }
}
