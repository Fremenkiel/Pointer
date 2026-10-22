import CanvasFeature
import Model
import Rendering

/// One open of a card or one leave: the path of the canvas to show, the end of the flight, and
/// the new screen when its first frame is ready (architecture.md 6.2 and 6.3, D-98, D-109).
@MainActor
final class CardOpening {
    /// The longest wait for the first frame of the child.
    private static let timeout = Duration.seconds(5)
    /// The wait between two looks at the renderer of the child: about one frame at 120 Hz.
    private static let pollInterval = Duration.milliseconds(4)

    /// The path of the canvas to show.
    let target: NavigationPath
    /// `true` after the flight of the shown screen ended.
    var isFlightDone = false
    /// `true` for a leave after a pinch-out exit: the child already shrank into its card, so the
    /// parent shows at the camera of CARD-04 at once (CARD-05).
    var isPinch = false
    /// The card of a leave in the parent canvas, after the load of the parent.
    var card: Card?
    /// The new screen after its first frame, or `nil`.
    var canvas: CanvasViewController?
    /// The new screen from the moment it joins the container, so that a cancel or a failure
    /// can remove it, or `nil`.
    var added: CanvasViewController?
    /// `false` while the preview of the child of a leave renders (D-111).
    var isPreviewDone = true
    /// The new preview of the child of a leave, or `nil`.
    var preview: PreviewImage?

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
