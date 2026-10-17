import Geometry
import Synchronization
import Testing

@testable import Rendering

/// Counts the calls of a wake function.
private final class WakeCounter: Sendable {
    private let count = Atomic<Int>(0)

    /// Adds one call.
    func wake() { count.add(1, ordering: .relaxed) }

    /// The calls so far.
    var calls: Int { count.load(ordering: .relaxed) }
}

@Suite("Render engine inbox")
struct RenderEngineTests {
    private func makeEngine(counter: WakeCounter) throws -> RenderEngine {
        let engine = try RenderEngine(configuration: RendererConfiguration()) { _ in }
        engine.post { $0.wake = { counter.wake() } }
        return engine
    }

    @Test("An idle frame loop sleeps, and the next change wakes it once")
    func sleepAndWake() throws {
        let counter = WakeCounter()
        let engine = try makeEngine(counter: counter)
        #expect(engine.sleepIfIdle())
        engine.post { box in
            box.camera = Camera(center: Point(x: 1, y: 0), zoom: 1)
            box.hasNewCamera = true
        }
        engine.post { $0.hasNewCamera = true }
        #expect(counter.calls == 1)
    }

    @Test("A frame loop with a waiting change does not sleep")
    func noSleepWithChange() throws {
        let counter = WakeCounter()
        let engine = try makeEngine(counter: counter)
        engine.post { $0.viewport = (Size(width: 100, height: 100), 2) }
        #expect(!engine.sleepIfIdle())
        engine.post { $0.hasNewCamera = true }
        #expect(counter.calls == 0)
    }
}
