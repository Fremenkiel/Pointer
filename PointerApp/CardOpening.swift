import CanvasFeature
import Model

/// One open of a card: the path of the child, the end of the flight, and the child screen
/// when its first frame is ready (architecture.md 6.2, D-98).
@MainActor
final class CardOpening {
    /// The longest wait for the first frame of the child.
    private static let timeout = Duration.seconds(5)
    /// The wait between two looks at the renderer of the child: about one frame at 120 Hz.
    private static let pollInterval = Duration.milliseconds(4)

    /// The path of the child canvas.
    let target: NavigationPath
    /// `true` after the flight of the parent ended.
    var isFlightDone = false
    /// The child screen after its first frame, or `nil`.
    var canvas: CanvasViewController?

    init(target: NavigationPath) {
        self.target = target
    }

    /// The first frame of the child did not come in time.
    struct FirstFrameTimedOut: Error {}

    /// Waits until the renderer of `canvas` drew a frame with all strokes of the load.
    ///
    /// - Throws: `FirstFrameTimedOut` after 5 s, or `CancellationError`.
    static func waitForFirstFrame(of canvas: CanvasViewController) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !canvas.hasDrawnLoad {
            guard clock.now < deadline else { throw FirstFrameTimedOut() }
            try await Task.sleep(for: pollInterval)
        }
    }
}
