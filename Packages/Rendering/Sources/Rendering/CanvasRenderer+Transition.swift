import Model
import os

/// The open and the leave of a card on the renderer of the parent canvas (architecture.md 6.2
/// and 6.3, D-98, D-108, D-109, D-110).
extension CanvasRenderer {
    /// The crossfade from the preview to the first frame of the child, and back for a leave
    /// (D-98). The canvas fades the view of the child with it.
    public static let crossfadeDuration = 0.1

    /// Starts the open of `card`. The next frame copies the shown image into one texture and
    /// frees the committed textures and the eraser mask. Until the end, each frame draws the
    /// copy with the parent weight and the card on top at full weight. The weight starts at 1.
    public func beginOpen(of card: CardID) {
        let start = TransitionStart(card: card, isOpen: true)
        engine.post { box in
            box.transitionStart = start
            box.transitionWeight = nil
        }
    }

    /// Starts the leave of a child into `card` on the loaded parent. Each frame draws the
    /// parent with the parent weight and the card on top at full weight. The weight starts at 0.
    public func beginLeave(into card: CardID) {
        let start = TransitionStart(card: card, isOpen: false)
        engine.post { box in
            box.transitionStart = start
            box.transitionWeight = nil
        }
    }

    /// Sets the weight of the parent image of the running transition: 1 shows the parent in
    /// full, 0 shows the card alone. The camera animation sets it each frame (m6-plan.md
    /// section 4, rule 7).
    ///
    /// - Precondition: `weight` is from 0 to 1.
    public func setParentWeight(_ weight: Double) {
        precondition((0...1).contains(weight), "A parent weight is from 0 to 1, got \(weight)")
        engine.post { box in box.transitionWeight = weight }
    }

    /// Shows or moves a pinch-out exit of this child canvas (CARD-05, D-109): the child shrinks
    /// into its card frame over the frozen image of its parent, by the progress of `exit`.
    public func showPinchExit(_ exit: PinchExit) {
        precondition((0...1).contains(exit.progress), "A progress is from 0 to 1")
        engine.post { box in
            box.pinchExit = exit
            box.endsPinchExit = false
        }
    }

    /// Ends a pinch-out exit: the child shows as before.
    public func endPinchExit() {
        engine.post { box in
            box.pinchExit = nil
            box.endsPinchExit = true
        }
    }

    /// The most tries of the handoff of the parent image while frames hold the locks: with
    /// `parentImageWait`, about 1 s. A frame holds its lock for a few milliseconds.
    static let parentImageTries = 500
    /// The wait before the next try of the handoff of the parent image.
    static let parentImageWait = Duration.milliseconds(2)

    /// Gives the frozen copy of this parent to the renderer of its child at the end of an open,
    /// for the pinch-out exit of the child (D-109). If a frame holds a lock, the handoff tries
    /// again on a later turn of the main run loop, so the main actor never waits for a frame.
    public func giveParentImage(to child: CanvasRenderer) {
        precondition(child !== self, "A parent gives its image to another renderer")
        guard !engine.tryGiveParentImage(to: child.engine) else { return }
        // A frame holds a lock. Each later turn tries again, once per open (PERF-02).
        let (parent, child) = (engine, child.engine)
        Task { @MainActor in
            for _ in 0..<Self.parentImageTries {
                do {
                    try await Task.sleep(for: Self.parentImageWait)
                } catch {
                    return
                }
                if parent.tryGiveParentImage(to: child) { return }
            }
            Logger(subsystem: "dk.saarikivi.pointer", category: "Rendering")
                .error("The frozen parent image did not reach the child")
        }
    }

    /// Plays `flight` on the render thread (D-121): each frame takes its camera, and the
    /// effect of the flight, from the closed form at the target time of the frame, also while
    /// the main thread is blocked. The next camera from the main thread ends the flight.
    public func fly(_ flight: RenderFlight) {
        engine.post { box in
            box.flight = flight
            box.endsFlight = false
        }
    }

    /// Ends the transition. A renderer whose committed textures went makes new ones.
    public func endTransition() {
        engine.post { box in box.endsTransition = true }
    }
}
