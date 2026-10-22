import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The camera at rest reaches the device state only inside the zoom range. A flight of an open
/// rested at the cover zoom of a small card, above 8, and the store stopped the app (fix of
/// 2026-10-22, TEST-03).
@MainActor
@Suite("Camera at rest")
struct CameraRestTests {
    /// The cameras that the canvas reported at rest.
    final class Rests {
        var cameras: [Camera] = []
    }

    @Test("An open of a small card reports no camera at rest outside the zoom range")
    func openOfSmallCard() async throws {
        let host = try OnScreenCanvas.host()
        var content = CanvasContent(canvasID: Fixtures.canvas)
        // A card of the minimum size covers the screen far above zoom 8.
        let frame = Rect(origin: .zero, size: Size(width: 64, height: 48))
        let card = try NewCardTests.card(1, frame: frame)
        try content.add(card)
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        let rests = Rests()
        dependencies.onCameraRest = { rests.cameras.append($0) }
        let controller = CanvasViewController(dependencies: dependencies)
        OnScreenCanvas.show(controller, in: host)
        defer { OnScreenCanvas.close(controller) }
        var ended = false
        controller.beginOpen(of: card) { ended = true }
        for _ in 0..<200 where !ended {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(ended)
        #expect(rests.cameras.allSatisfy { Limits.zoomRange.contains($0.zoom) }, "\(rests.cameras)")
    }
}
