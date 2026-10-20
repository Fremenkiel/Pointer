import Geometry
import Model

/// The changes of the strokes and the eraser input that a frame takes from the inbox.
extension FrameRenderer {
    /// Applies one edit: it removes strokes, notes their area for a redraw in the next frame,
    /// and adds the new strokes (D-66). A removed ID that the store does not hold is ignored.
    ///
    /// - Precondition: The renderer holds room for the added strokes.
    func apply(_ edit: RenderEdit) {
        precondition(
            store.count + edit.added.count <= Limits.maxStrokesAfterErase + edit.removed.count,
            "Too many strokes"
        )
        for id in edit.removed {
            guard let bounds = store.bounds(of: id) else { continue }
            // The next frame is the first one that can no longer read the stroke.
            store.remove(id, frame: frame + 1)
            if edit.area == nil {
                dirtyArea = dirtyArea.map { Self.union($0, bounds) } ?? bounds
            }
        }
        if let area = edit.area {
            dirtyArea = dirtyArea.map { Self.union($0, area) } ?? area
        }
        for stroke in edit.added {
            let slot = store.add(stroke)
            if edit.area == nil {
                pendingSlots.append(slot)
            } else {
                layer?.addToBuild(slot)
            }
        }
    }

    /// Applies the eraser input of a frame: a start, new samples in view space, and an end, in
    /// this order. The camera of the frame converts the samples to canvas space.
    func applyEraser(start radius: Double?, samples: [Point], ends: Bool) {
        if let radius {
            precondition(radius > 0, "Eraser radius must be positive, got \(radius)")
            eraserMask.begin(radius: radius / camera.zoom)
        }
        for sample in samples {
            eraserMask.append(camera.canvasPoint(fromView: sample, viewSize: viewSize))
        }
        if ends {
            eraserMask.end()
        }
        assert(!ends || !eraserMask.isActive, "An ended gesture is not active")
    }

    /// Notes that the edits of handoff number `handoff` wait for the screen.
    ///
    /// - Precondition: `handoff` is positive.
    func markHandoff(_ handoff: UInt64) {
        precondition(handoff > 0, "Handoff numbers start at 1")
        waitingHandoff = max(waitingHandoff, handoff)
    }

    private static func union(_ first: Rect, _ second: Rect) -> Rect {
        Rect(
            minX: min(first.minX, second.minX),
            minY: min(first.minY, second.minY),
            maxX: max(first.maxX, second.maxX),
            maxY: max(first.maxY, second.maxY)
        )
    }
}
