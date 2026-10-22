import Geometry
import InkEngine
import Model

/// The eraser tool: the mask while the pencil moves and one `EraseStrokes` at the lift
/// (architecture.md 4.4, D-30, D-66).
extension CanvasViewController {
    /// Starts an eraser gesture.
    func beginErase() {
        assert(eraserSamples == nil, "An eraser gesture is already running")
        // The list of the last gesture keeps its capacity (M-07).
        var samples = spareEraserSamples
        spareEraserSamples = []
        samples.removeAll(keepingCapacity: true)
        if samples.capacity < EraserTool.sampleCapacity {
            samples.reserveCapacity(EraserTool.sampleCapacity)
        }
        eraserSamples = samples
        pencilObserver.reportsCoalescedSamples = true
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
        pencilObserver.reportsCoalescedSamples = false
        defer { spareEraserSamples = samples }
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
                onCompleted: stepDrawnCallback(),
                onPresented: {}
            )
            // The send schedules the save of the rows (P-09).
            send(rows)
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
        let camera = cameraController.shownCamera
        let path = EraserPath(
            samples: samples.map { camera.canvasPoint(fromView: $0, viewSize: viewSize) },
            radius: EraserTool.canvasRadius(zoom: camera.zoom)
        )
        // A pass over the bounds of all strokes. It takes about 0.3 ms for 21,000 strokes, so
        // the canvas keeps no grid of its own (M4 task 3.5).
        // The one filter by the path bounds (P-10). `Eraser.command` takes the candidates as they
        // are.
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
}
