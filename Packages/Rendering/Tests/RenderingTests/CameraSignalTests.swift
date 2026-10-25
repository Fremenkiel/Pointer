import Foundation
import Geometry
import QuartzCore
import Synchronization
import Testing

@testable import Rendering

/// The wait of a frame for its camera (review after M8, section 3.2, item 4). The old post
/// signaled after the inbox lock. A wait could time out and reset in that gap, and the late
/// signal then ended the next wait at once.
@MainActor
@Suite("Camera signal of the frame loop")
struct CameraSignalTests {
    /// A flag that another thread sets.
    private final class Flag: Sendable {
        let isSet = Mutex(false)
    }

    /// Marks the camera as in motion with no new camera, so the next wait waits.
    private static func prepareWait(_ engine: RenderEngine) {
        engine.inbox.withLock { box in
            box.cameraMovedInLastFrame = true
            box.hasNewCamera = false
        }
    }

    /// Starts a thread that spins on the flag of a waiting frame and posts a camera at once,
    /// inside the wait of 3 ms. A poll of the main actor can miss it.
    private static func postCameraDuringWait(_ engine: RenderEngine) -> Flag {
        let posted = Flag()
        Thread.detachNewThread {
            // A `while` loop with a counter: a `for ... where` loop does not stop when its
            // condition turns, it only skips its body.
            var spins = 0
            while spins < 10_000_000, !engine.inbox.withLock({ $0.isWaitingForCamera }) {
                spins += 1
            }
            engine.post { box in
                box.camera = Camera(center: Point(x: 1, y: 0), zoom: 1)
                box.hasNewCamera = true
            }
            posted.isSet.withLock { $0 = true }
        }
        return posted
    }

    @Test("A camera that comes during a wait leaves no signal for the next wait")
    func noLateSignal() async throws {
        let budget = RenderEngine.cameraWaitBudget
        // The hook holds the post past the timeout and the reset of the waiting frame. It runs
        // only for a post that gave a waiting frame its camera.
        let hookRan = Flag()
        let renderer = try CanvasRenderer(
            configuration: RendererConfiguration(),
            previews: nil,
            afterTake: nil,
            afterCameraLock: {
                hookRan.isSet.withLock { $0 = true }
                Thread.sleep(forTimeInterval: budget * 4)
            }
        )
        let engine = renderer.engine
        Self.prepareWait(engine)
        let posted = Self.postCameraDuringWait(engine)
        let done = Flag()
        Thread.detachNewThread {
            engine.waitForCameraIfMoving()
            done.isSet.withLock { $0 = true }
        }
        for _ in 0..<1_000 where !posted.isSet.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(hookRan.isSet.withLock { $0 }, "The camera came during the wait")
        for _ in 0..<1_000 where !done.isSet.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(1))
        }
        // The next frame finds no new camera, so it waits the whole budget.
        Self.prepareWait(engine)
        let start = CACurrentMediaTime()
        engine.waitForCameraIfMoving()
        let waited = CACurrentMediaTime() - start
        #expect(waited >= budget * 0.8, "The next wait took \(waited) s of \(budget) s")
    }
}
