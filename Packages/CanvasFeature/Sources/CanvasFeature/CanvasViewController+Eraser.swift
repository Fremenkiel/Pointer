import Geometry
import InkEngine
import Model

/// The eraser tool: the mask while the pencil moves and one `EraseStrokes` at the lift
/// (architecture.md 4.4, D-30, D-66).
extension CanvasViewController {
    /// Starts an eraser gesture.
    func beginErase() {
        assert(eraserSamples == nil, "An eraser gesture is already running")
        var samples: [Point] = []
        samples.reserveCapacity(EraserTool.sampleCapacity)
        eraserSamples = samples
        renderer.beginErase(radius: EraserTool.radius)
    }

    /// Adds one sample in view space. A sample past `EraserPath.maxSamples` is ignored.
    func addEraserSample(_ location: Point) {
        guard var samples = eraserSamples, samples.count < EraserPath.maxSamples else { return }
        eraserSamples = nil
        samples.append(location)
        eraserSamples = samples
        renderer.addEraserSample(location)
    }

    /// Ends the gesture. At a lift, it cuts the strokes under the path, applies one
    /// `EraseStrokes`, and sends the change to the renderer and the rows to the library. A
    /// cancelled touch changes nothing.
    func finishErase(isCancelled: Bool) {
        guard let samples = eraserSamples else { return }
        eraserSamples = nil
        let size = Size(width: canvasView.bounds.width, height: canvasView.bounds.height)
        guard !isCancelled, !samples.isEmpty, size.width > 0, size.height > 0,
            let command = eraseCommand(samples: samples, viewSize: size)
        else {
            renderer.endErase()
            return
        }
        do {
            let rows = try perform(command)
            renderer.change(
                removing: command.removed.map(\.id),
                adding: command.parts,
                area: command.area,
                onPresented: { [weak self] in self?.onStepPresented?() }
            )
            send(rows)
            requestSave()
        } catch {
            logger.error("An erase did not apply: \(String(describing: error))")
        }
        renderer.endErase()
    }

    /// Returns the command of a gesture, or `nil` if the path touches no stroke.
    private func eraseCommand(samples: [Point], viewSize: Size) -> EraseStrokes? {
        precondition(!samples.isEmpty, "An eraser path needs a sample")
        CanvasSignpost.begin("EraseSplit")
        defer { CanvasSignpost.end("EraseSplit") }
        let camera = cameraController.camera
        let path = EraserPath(
            samples: samples.map { camera.canvasPoint(fromView: $0, viewSize: viewSize) },
            radius: EraserTool.canvasRadius(zoom: camera.zoom)
        )
        // A pass over the bounds of all strokes. It takes about 0.3 ms for 21,000 strokes, so
        // the canvas keeps no grid of its own (M4 task 3.5).
        let bounds = path.bounds
        let candidates = content.strokes.values.filter { $0.bounds.intersects(bounds) }
        guard
            let command = Eraser.command(erasing: candidates, along: path, factory: &clock.factory)
        else { return nil }
        let count = content.strokes.count - command.removed.count + command.parts.count
        guard count > Limits.maxStrokesAfterErase else { return command }
        // The parts would pass the bound after an erase, so the strokes go whole (D-73).
        return EraseStrokes(removed: command.removed, parts: [], area: nil)
    }

    /// Asks the library for a save, as at the pencil lift of the pen (D-27).
    func requestSave() {
        guard let repository else { return }
        Task { await repository.requestSave() }
    }
}
