import Foundation
import Geometry
import Metal
import Model
import QuartzCore
import Synchronization
import Testing

@testable import Rendering

/// A completion of a preview render that calls back into its own renderer (review after M9,
/// section 3.2, item 2). Under the old code, the completion ran under the inbox lock or the frame
/// lock, and the second lock of the same `Mutex` stopped the app.
@MainActor
@Suite("Completions of a preview render")
struct PreviewCompletionLockTests {
    private static let camera = Camera(center: .zero, zoom: 1)

    /// A flag that the completion sets on another thread.
    private final class Flag: Sendable {
        let isSet = Mutex(false)
    }

    private static func layer(for renderer: CanvasRenderer) -> CAMetalLayer {
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return layer
    }

    /// Waits up to 2 s for `flag`.
    private static func wait(for flag: Flag) async throws {
        for _ in 0..<2_000 where !flag.isSet.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test("A replaced request ends after the inbox lock, so its completion can post")
    func replacedInInbox() async throws {
        let renderer = try CanvasRenderer()
        let engine = renderer.engine
        let ended = Flag()
        renderer.renderPreview(camera: Self.camera, cardAspect: 1) { image in
            engine.post { _ in }
            ended.isSet.withLock { $0 = image == nil }
        }
        // The second request replaces the first one inside the inbox.
        renderer.renderPreview(camera: Self.camera, cardAspect: 1) { _ in }
        try await Self.wait(for: ended)
        #expect(ended.isSet.withLock { $0 })
    }

    @Test("A replaced job ends after the frame lock, so its completion can use the frame work")
    func replacedInFrame() async throws {
        let renderer = try CanvasRenderer()
        let engine = renderer.engine
        let layer = Self.layer(for: renderer)
        let ended = Flag()
        renderer.renderPreview(camera: Self.camera, cardAspect: 1) { image in
            engine.withRenderer { _ in }
            ended.isSet.withLock { $0 = $0 || image == nil }
        }
        // The frame starts the first job. The next frame replaces it with the second request.
        _ = renderer.renderFrame(into: layer, deadline: nil)
        renderer.renderPreview(camera: Self.camera, cardAspect: 1) { _ in }
        _ = renderer.renderFrame(into: layer, deadline: nil)
        try await Self.wait(for: ended)
        #expect(ended.isSet.withLock { $0 })
    }
}
