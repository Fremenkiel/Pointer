import Geometry

/// The transition commands of the engine (D-98).
extension RenderEngine {
    /// Applies the end, the start, and the weight of a transition, in this order, so that a new
    /// start after an end in the same frame wins.
    static func applyTransition(_ input: RenderInput, to renderer: FrameRenderer) {
        precondition(input.transitionWeight.map { (0...1).contains($0) } ?? true, "Weight")
        if input.endsTransition, renderer.transition != nil {
            renderer.transition = nil
        }
        if let start = input.transitionStart {
            // An open starts with the parent in full, a leave with the card alone.
            renderer.transition = FrameTransition(
                card: start.card,
                parentWeight: start.isOpen ? 1 : 0,
                freezes: start.isOpen,
                frozen: nil
            )
        }
        if let weight = input.transitionWeight {
            renderer.transition?.parentWeight = weight
        }
        if input.endsPinchExit { renderer.pinchExit = nil }
        if let exit = input.pinchExit { renderer.pinchExit = exit }
        if input.endsFlight { renderer.flight = nil }
        if let flight = input.flight { renderer.flight = flight }
        assert(
            renderer.transition.map { (0...1).contains($0.parentWeight) } ?? true,
            "A parent weight is from 0 to 1"
        )
    }

    /// Moves the camera, the parent weight, and the pinch-out exit along the flight to `time`,
    /// the target time of the frame (D-121). The values of the flight replace the camera and
    /// the weights from the main thread, which can be late. After its end, the flight holds its
    /// last values until a camera from the main thread ends it.
    ///
    /// - Precondition: `time` is finite.
    /// - Returns: `true` if the frame must draw: the flight runs or changed a value.
    static func stepFlight(_ renderer: FrameRenderer, at time: Double) -> Bool {
        precondition(time.isFinite, "A frame time is finite, got \(time)")
        guard let current = renderer.flight else { return false }
        RenderSignpost.begin("Flight")
        let camera = current.shownCamera(at: time)
        var isChanged = camera != renderer.camera
        renderer.camera = camera
        let progress = current.flight.progress(at: time)
        switch current.effect {
        case .none:
            break
        case .open:
            isChanged = setParentWeight(1 - progress, of: renderer) || isChanged
        case .leave:
            isChanged = setParentWeight(progress, of: renderer) || isChanged
        case .pinchExit(let minimumZoom, let exitZoom):
            let exit = PinchExit.progress(
                zoom: current.flight.camera(at: time).zoom,
                minimumZoom: minimumZoom,
                exitZoom: exitZoom
            )
            isChanged = setExitProgress(exit, of: renderer) || isChanged
        }
        RenderSignpost.end("Flight")
        assert((0...1).contains(progress), "The progress \(progress) is from 0 to 1")
        return isChanged || time < current.flight.end
    }

    /// Sets the parent weight of a running transition. Returns `true` if it changed.
    private static func setParentWeight(_ weight: Double, of renderer: FrameRenderer) -> Bool {
        guard let transition = renderer.transition, transition.parentWeight != weight else {
            return false
        }
        renderer.transition?.parentWeight = weight
        return true
    }

    /// Sets the progress of a running pinch-out exit. Returns `true` if it changed.
    private static func setExitProgress(_ progress: Double, of renderer: FrameRenderer) -> Bool {
        guard let exit = renderer.pinchExit, exit.progress != progress else { return false }
        renderer.pinchExit?.progress = progress
        return true
    }
}
