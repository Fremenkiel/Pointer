import Geometry
import Model
import Rendering
import UIKit

/// The open, the leave, and the pinch-out exit of a card on the canvas screen (architecture.md
/// 6.2 and 6.3, CARD-03 to CARD-05, D-98, D-109).
extension CanvasViewController {
    /// Starts the open of a card (architecture.md 6.2, D-98): the camera flies until the card
    /// covers the screen at the scale k = max(W / w, H / h), and the parent fades out under the
    /// card. Input is off until the end, so a second double tap does nothing. `onEnd` runs once
    /// at the end of the flight.
    public func beginOpen(of card: Card, onEnd: @escaping @MainActor () -> Void) {
        guard cardTransition == nil, viewSize.width > 0, viewSize.height > 0 else { return }
        endTextEdit()
        canvasView.isUserInteractionEnabled = false
        cardTransition = CardTransition(kind: .open, start: camera, onEnd: onEnd)
        renderer.beginOpen(of: card.id)
        cameraController.fly(to: Self.coverCamera(of: card.frame, viewSize: viewSize))
        canvasView.inkView.requestFrame()
        assert(cameraController.flightProgress != nil, "The open flies")
    }

    /// Ends an open or a leave that cannot finish, for example when the child does not load:
    /// the parent shows again at its camera before the flight, and input is on again.
    public func cancelCardTransition() {
        let start = cardTransition?.start
        cardTransition = nil
        renderer.endTransition()
        if let start { cameraController.fly(to: start) }
        canvasView.isUserInteractionEnabled = true
        canvasView.inkView.requestFrame()
    }

    /// `true` while an open, a leave, or the flight before a leave runs on this canvas.
    public var isInCardTransition: Bool { cardTransition != nil }

    /// `true` after the renderer drew a frame with all strokes of the load, and needs no more
    /// frames: the first frame of a canvas that opened.
    public var hasDrawnLoad: Bool {
        !renderer.needsMoreFrames && renderer.strokeCount >= content.strokes.count
    }

    /// The camera at which a card frame covers a screen of `viewSize` (D-98).
    ///
    /// - Precondition: The frame and the view have a size.
    public static func coverCamera(of frame: Rect, viewSize: Size) -> Camera {
        precondition(frame.size.width > 0 && frame.size.height > 0, "A card has a size")
        let zoom = max(viewSize.width / frame.size.width, viewSize.height / frame.size.height)
        return Camera(center: frame.center, zoom: zoom)
    }

    /// Sets the weight of the parent from the progress of the flight, and ends the transition
    /// with the flight. It runs in the frame callback and allocates nothing (PERF-01).
    func stepCardTransition() {
        guard let transition = cardTransition else { return }
        guard let progress = cameraController.flightProgress else {
            cardTransition = nil
            switch transition.kind {
            case .open: renderer.setParentWeight(0)
            case .leave:
                renderer.endTransition()
                canvasView.isUserInteractionEnabled = true
            case .settle, .exit: break
            }
            transition.onEnd()
            return
        }
        switch transition.kind {
        case .open: renderer.setParentWeight(1 - progress)
        case .leave: renderer.setParentWeight(progress)
        case .settle, .exit: break
        }
    }

    /// Shows the pinch-out exit of a child below the minimum zoom, by the progress of the camera
    /// (CARD-05, D-109). It runs at each pinch step and each camera step, and ends the exit when
    /// the camera is back at the minimum zoom. It allocates nothing per frame (PERF-01).
    func updatePinchExit() {
        guard level > 0 else { return }
        let progress = cameraController.exitProgress
        guard progress > 0 else {
            if parentLink.exit != nil {
                parentLink.exit = nil
                renderer.endPinchExit()
            }
            return
        }
        var exit = parentLink.exit ?? makePinchExit()
        exit.progress = progress
        parentLink.exit = exit
        renderer.showPinchExit(exit)
    }

    /// The exit of this child: from the cover camera of its card to the camera of CARD-04.
    private func makePinchExit() -> PinchExit {
        guard let card = parentLink.card else {
            let camera = Camera(center: .zero, zoom: Limits.standardZoom)
            return PinchExit(card: nil, cover: camera, leave: camera)
        }
        return PinchExit(
            card: card.frame,
            cover: Self.coverCamera(of: card.frame, viewSize: viewSize),
            leave: Camera(center: card.frame.center, zoom: Limits.standardZoom)
        )
    }

    /// Plays the minimize animation after a lift under the threshold (CARD-05, D-104): input
    /// goes off, and the camera flies to the end of the exit. Then the app leaves for the parent.
    func startPinchLeave() {
        endTextEdit()
        canvasView.isUserInteractionEnabled = false
        let onLeave = parentLink.onLeave
        cardTransition = CardTransition(kind: .exit, start: camera, onEnd: onLeave)
        cameraController.fly(to: cameraController.exitCamera)
        canvasView.inkView.requestFrame()
    }

    /// Gives the frozen copy of this parent frame to the child after an open (D-109).
    public func giveParentImage(to child: CanvasViewController) {
        renderer.giveParentImage(to: child.renderer)
    }

    /// Prepares the leave of this canvas into its card (D-109): input goes off, and the camera
    /// flies to the camera of the open, so that the child shows what the preview shows. `onEnd`
    /// runs at the end of the flight, at once if the camera is there already.
    public func prepareLeave(onEnd: @escaping @MainActor () -> Void) {
        guard cardTransition == nil else { return }
        endTextEdit()
        canvasView.isUserInteractionEnabled = false
        let target = content.openCamera
        guard target != camera else {
            onEnd()
            return
        }
        cardTransition = CardTransition(kind: .settle, start: camera, onEnd: onEnd)
        cameraController.fly(to: target)
        canvasView.inkView.requestFrame()
    }

    /// Shows only the card that the child of a leave covers: the parent at weight 0 under the
    /// card, input off (D-108). The canvas opens at the cover camera of the card. `runLeave`
    /// then plays the leave.
    public func holdLeave(into card: Card) {
        canvasView.isUserInteractionEnabled = false
        renderer.beginLeave(into: card.id)
        renderer.setParentWeight(0)
    }

    /// Plays the leave: the camera flies from the card to the camera of CARD-04, the standard
    /// zoom centered on the card, while the parent fades in (D-98, D-99). `onEnd` runs at the
    /// end, when the transition is over and input is on again.
    public func runLeave(into card: Card, onEnd: @escaping @MainActor () -> Void) {
        guard cardTransition == nil else { return }
        cardTransition = CardTransition(kind: .leave, start: camera, onEnd: onEnd)
        cameraController.fly(to: Camera(center: card.frame.center, zoom: Limits.standardZoom))
        canvasView.inkView.requestFrame()
    }
}
