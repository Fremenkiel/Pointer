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
                dirtyArea = dirtyArea?.union(bounds) ?? bounds
            }
        }
        if let area = edit.area {
            dirtyArea = dirtyArea?.union(area) ?? area
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

    /// Adds the laid-out boxes of a load and redraws the text of their area (D-92). A box that an
    /// edit changed during the load keeps the edit.
    func insert(_ loaded: [TextStore.LaidOut]) {
        precondition(loaded.count <= Limits.maxNodesPerCanvas, "Too many text boxes")
        for item in loaded where !textEditedDuringLoad.contains(item.box.id) {
            texts.insert(item.box, layout: item.layout)
            guard let bounds = texts.entries[item.box.id]?.bounds else { continue }
            dirtyTextArea = dirtyTextArea?.union(bounds) ?? bounds
        }
        assert(texts.count <= Limits.maxNodesPerCanvas, "The store holds at most the node limit")
    }

    /// Applies one text edit: it changes the text store and notes the old and the new bounds
    /// for a text redraw in the next frame (D-82).
    func apply(_ edit: TextEdit) {
        switch edit {
        case .change(let removed, let added):
            precondition(
                removed.count + added.count <= Limits.maxNodesPerCanvas,
                "Too many text boxes in one edit"
            )
            for id in removed {
                if textLoadsInFlight > 0 { textEditedDuringLoad.insert(id) }
                guard let bounds = texts.remove(id) else { continue }
                dirtyTextArea = dirtyTextArea?.union(bounds) ?? bounds
            }
            for box in added { place(box) }
        case .place(let box):
            place(box)
        }
    }

    /// Puts a box in the store and notes its old and new bounds for the text redraw.
    private func place(_ box: TextBox) {
        if textLoadsInFlight > 0 { textEditedDuringLoad.insert(box.id) }
        let earlier = texts.add(box)
        assert(texts.entries[box.id] != nil, "The placed box \(box.id) is held")
        guard let bounds = texts.entries[box.id]?.bounds else { return }
        let area = earlier?.union(bounds) ?? bounds
        dirtyTextArea = dirtyTextArea?.union(area) ?? area
    }

    /// Starts the redraw of the text that changed since the last frame, and goes on with a
    /// running text redraw (D-82).
    func encodeTextChange(layer: CommittedLayer, context: FrameContext) {
        precondition(layer.front == nil || layer.drawableWidth > 0, "A layer has a drawable size")
        // New previews redraw the front texture between builds. A build draws each card with
        // the preview that the atlas holds at that moment.
        if layer.build == nil, let previews, let area = previews.dirtyArea {
            dirtyTextArea = dirtyTextArea?.union(area) ?? area
            previews.dirtyArea = nil
        }
        if let area = dirtyTextArea {
            layer.textChanged(area, texts: texts, cards: cards)
            dirtyTextArea = nil
        }
        layer.continueTextRedraw(text: textEncoder, context: context)
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

    /// Notes that the edits of handoff number `handoff` wait for the screen, and whether one of
    /// them asks for the GPU end of its frame.
    ///
    /// - Precondition: `handoff` is positive.
    func markHandoff(_ handoff: UInt64, wantsCompletion: Bool = false) {
        precondition(handoff > 0, "Handoff numbers start at 1")
        waitingHandoff = max(waitingHandoff, handoff)
        waitingCompletion = waitingCompletion || wantsCompletion
    }
}
