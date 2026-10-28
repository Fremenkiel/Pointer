import Foundation
import Geometry
import Metal
import Model
import QuartzCore
import Synchronization
import Testing

@testable import Rendering

/// The handoff of the frozen parent image at the end of an open (D-109). The main actor calls
/// it, so it must not wait while a render thread holds its frame lock (review after M9, section
/// 3.2, item 3).
@MainActor
@Suite("Handoff of the parent image")
struct ParentImageHandoffTests {
    /// How long the test holds the frame lock of the parent on another thread.
    private static let hold = 0.2
    /// The longest call on the main actor that the test accepts while the lock is held.
    private static let maxCallSeconds = 0.02

    private static func layer(for renderer: CanvasRenderer) -> CAMetalLayer {
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return layer
    }

    @Test("The handoff waits for the completion of the freeze command buffer (3.2.13)")
    func waitsForFreeze() async throws {
        let parent = try CanvasRenderer()
        let layer = Self.layer(for: parent)
        let frame = Rect(origin: Point(x: -60, y: -25), size: Size(width: 120, height: 60))
        let card = try CardStoreTests.card(1, frame: frame, title: "Tree")
        parent.load([card])
        for _ in 0..<2_000 where parent.isLoading {
            _ = parent.renderFrame(into: layer, deadline: nil)
            try await Task.sleep(for: .milliseconds(1))
        }
        parent.beginOpen(of: card.id)
        for _ in 0..<10 where parent.renderFrame(into: layer, deadline: nil) {}
        let child = try CanvasRenderer()
        #expect(parent.engine.withRenderer { $0.transition?.frozen != nil })
        // The test stands in for the GPU: a flag that no completion set yet.
        parent.engine.withRenderer { $0.transition?.frozenCompletion = CompletionFlag() }
        #expect(!parent.engine.tryGiveParentImage(to: child.engine))
        #expect(child.engine.withRenderer { $0.parentImage == nil })
        parent.engine.withRenderer { $0.transition?.frozenCompletion.set() }
        #expect(parent.engine.tryGiveParentImage(to: child.engine))
        #expect(child.engine.withRenderer { $0.parentImage != nil })
    }

    @Test("A held frame lock of the parent does not stop the main actor, and the image arrives")
    func heldParentLock() async throws {
        let parent = try CanvasRenderer()
        let layer = Self.layer(for: parent)
        let frame = Rect(origin: Point(x: -60, y: -25), size: Size(width: 120, height: 60))
        let card = try CardStoreTests.card(1, frame: frame, title: "Tree")
        parent.load([card])
        for _ in 0..<2_000 where parent.isLoading {
            _ = parent.renderFrame(into: layer, deadline: nil)
            try await Task.sleep(for: .milliseconds(1))
        }
        parent.beginOpen(of: card.id)
        // The first frame of the open freezes the parent.
        for _ in 0..<10 where parent.renderFrame(into: layer, deadline: nil) {}
        let child = try CanvasRenderer()
        let engine = parent.engine
        let hold = Self.hold
        let isHeld = Mutex(false)
        Thread.detachNewThread {
            engine.withRenderer { _ in
                isHeld.withLock { $0 = true }
                Thread.sleep(forTimeInterval: hold)
            }
        }
        for _ in 0..<1_000 where !isHeld.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(1))
        }
        let start = CACurrentMediaTime()
        parent.giveParentImage(to: child)
        let seconds = CACurrentMediaTime() - start
        #expect(seconds < Self.maxCallSeconds, "The call took \(seconds) s")
        var hasImage = false
        for _ in 0..<1_000 where !hasImage {
            try await Task.sleep(for: .milliseconds(2))
            hasImage = child.engine.withRenderer { $0.parentImage != nil }
        }
        #expect(hasImage, "The child gets the frozen copy after the lock")
    }
}
