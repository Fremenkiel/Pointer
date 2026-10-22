import QuartzCore
import Testing

@testable import Rendering

/// The render thread and its engine go away after a stop, also when a wake from another thread
/// comes after the stop (D-42).
@MainActor
@Suite("Render thread lifetime")
struct RenderThreadLifetimeTests {
    /// The longest wait for the thread to end.
    private static let timeout = Duration.seconds(2)

    @Test(
        "A wake after the stop does not keep the thread and the engine",
        arguments: [false, true]
    )
    func wakeAfterStop(isWokenLate: Bool) async throws {
        weak var weakThread: RenderThread?
        weak var weakEngine: RenderEngine?
        do {
            let engine = try RenderEngine(configuration: RendererConfiguration()) { _ in }
            let layer = CAMetalLayer()
            layer.device = engine.device
            let thread = RenderThread(engine: engine, layer: layer, frameRates: InkView.frameRates)
            weakThread = thread
            weakEngine = engine
            thread.start()
            thread.stop()
            // A post from a text layout or a preview load read the wake function before the stop,
            // and calls it after the run loop ended.
            if isWokenLate {
                try await Task.sleep(for: .milliseconds(100))
                thread.wake()
            }
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.timeout)
        while weakThread != nil || weakEngine != nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(weakThread == nil, "The render thread stays")
        #expect(weakEngine == nil, "The engine stays")
    }
}
