import Metal
import QuartzCore
import Synchronization
import Testing

@testable import Rendering

/// A drawable that the test presents by hand.
private final class FakeDrawable: NSObject, CAMetalDrawable {
    let texture: any MTLTexture
    let layer: CAMetalLayer
    private let handlers = Mutex<[MTLDrawablePresentedHandler]>([])

    init(texture: any MTLTexture, layer: CAMetalLayer) {
        self.texture = texture
        self.layer = layer
    }

    var presentedTime: CFTimeInterval { 0 }
    var drawableID: Int { 0 }

    func present() {}
    func present(at presentationTime: CFTimeInterval) {}
    func present(afterMinimumDuration duration: CFTimeInterval) {}

    func addPresentedHandler(_ block: @escaping MTLDrawablePresentedHandler) {
        handlers.withLock { $0.append(block) }
    }

    /// Runs the presented handlers, as Metal does after the present.
    func finishPresent() {
        let blocks = handlers.withLock { $0 }
        for block in blocks { block(self) }
    }
}

/// The handoff table keyed by the identity of the drawable (review of 2026-10-28, 3.2.19).
@MainActor
@Suite("Presented handoffs")
struct PresentedHandoffTests {
    @Test("A handoff of a drawable that is never presented does not fire for a later one")
    func staleHandoffDoesNotFire() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        // One object stands for two drawables with the same identifier: the first is never
        // presented, and the second takes its place.
        let drawable = FakeDrawable(texture: texture, layer: CAMetalLayer())
        let fired = Mutex<[UInt64]>([])
        PresentedHandoffs.attach(1, to: drawable) { handoff in fired.withLock { $0.append(handoff) }
        }
        PresentedHandoffs.attach(2, to: drawable) { handoff in fired.withLock { $0.append(handoff) }
        }
        drawable.finishPresent()
        #expect(fired.withLock { $0 } == [2])
    }
}
