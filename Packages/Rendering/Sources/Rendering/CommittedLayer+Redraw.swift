import Geometry

/// The redraw of a changed area, which can take more than one frame (D-66, F-05).
extension CommittedLayer {
    /// The redraw of one texture that goes on in the next frame when the draw list is full
    /// (F-05). The first pass clears the area, the later passes only draw.
    struct Redraw {
        let target: InkTarget
        var options: InkPassOptions
        var cursor = 0
    }

    /// `true` while a redraw has strokes left for the next frames.
    var isRedrawing: Bool { frontRedraw != nil || buildRedraw != nil }

    /// Clears a canvas area in the front texture and in a running build, and draws the strokes
    /// of the store there again (architecture.md 5.2, D-66). A full draw list leaves the other
    /// strokes for `continueRedraw`. A redraw that runs already starts again with both areas.
    ///
    /// The ink blends with `max`, so a removed stroke cannot be subtracted. A build that has not
    /// drawn yet needs nothing, because it skips the removed strokes.
    ///
    /// - Precondition: `area` is finite.
    func redraw(_ area: Rect, store: StrokeStore, encoder: InkEncoder, context: FrameContext) {
        precondition(area.origin.isFinite, "Redraw area is not finite")
        let whole = redrawArea.map { Self.union($0, area) } ?? area
        redrawArea = whole
        frontRedraw = front.flatMap { start(whole, in: $0, store: store, slots: &redrawSlots) }
        buildRedraw = build.flatMap { current in
            current.hasCleared
                ? start(whole, in: current.target, store: store, slots: &buildRedrawSlots) : nil
        }
        continueRedraw(encoder: encoder, context: context)
        assert(!isRedrawing || redrawArea != nil, "A running redraw keeps its area")
    }

    /// Draws the strokes of a running redraw until the draw list is full. A texture that the
    /// screen no longer shows and no build draws into is dropped from the redraw.
    func continueRedraw(encoder: InkEncoder, context: FrameContext) {
        guard isRedrawing else { return }
        assert(redrawArea != nil, "A running redraw has an area")
        RenderSignpost.begin("Redraw")
        defer { RenderSignpost.end("Redraw") }
        frontRedraw = frontRedraw.flatMap {
            draw($0, slots: redrawSlots, encoder: encoder, context: context)
        }
        buildRedraw = buildRedraw.flatMap {
            draw($0, slots: buildRedrawSlots, encoder: encoder, context: context)
        }
        if !isRedrawing { redrawArea = nil }
    }

    /// Lists the strokes of `area` in a target, or returns `nil` if the area misses it.
    private func start(
        _ area: Rect,
        in target: InkTarget,
        store: StrokeStore,
        slots: inout [Int]
    ) -> Redraw? {
        precondition(area.origin.isFinite, "Redraw area is not finite")
        guard let scissor = Self.scissor(for: area, in: target) else { return nil }
        assert(scissor.width > 0 && scissor.height > 0, "A redraw scissor holds pixels")
        // Only the part inside the texture changes pixels, so the query skips the rest (P-01).
        let margin = Self.redrawMarginPixels / target.pixelsPerCanvasPoint
        guard
            let clip = Self.intersection(
                area.expanded(by: margin),
                target.canvasRect.expanded(by: margin)
            )
        else { return nil }
        slots.removeAll(keepingCapacity: true)
        store.grid.forEachItem(touching: clip) { slots.append($0) }
        var options = InkPassOptions(clear: false, instanceBudget: .max)
        options.scissor = scissor
        options.clearsScissor = true
        options.clip = clip
        return Redraw(target: target, options: options)
    }

    /// Runs one pass of a redraw. The first pass clears the area, also without strokes.
    ///
    /// - Returns: The redraw with its new cursor, or `nil` if it is done or its texture is gone.
    private func draw(
        _ redraw: Redraw,
        slots: [Int],
        encoder: InkEncoder,
        context: FrameContext
    ) -> Redraw? {
        precondition(
            redraw.cursor <= slots.count,
            "Redraw cursor \(redraw.cursor) is past the list"
        )
        guard isLive(redraw.target) else { return nil }
        var next = redraw
        next.cursor = encoder.encodePass(
            context,
            target: redraw.target,
            slots: slots,
            cursor: redraw.cursor,
            options: redraw.options
        )
        next.options.clearsScissor = false
        assert(next.cursor >= redraw.cursor, "A redraw never goes back")
        return next.cursor < slots.count ? next : nil
    }

    /// `true` if the screen shows the target or a build draws into it.
    private func isLive(_ target: InkTarget) -> Bool {
        Self.isSame(front, target) || Self.isSame(build?.target, target)
    }

    private static func isSame(_ current: InkTarget?, _ target: InkTarget) -> Bool {
        guard let current else { return false }
        return current.texture === target.texture && current.camera == target.camera
    }

    /// Returns the common part of two rectangles, or `nil` if they do not overlap.
    private static func intersection(_ first: Rect, _ second: Rect) -> Rect? {
        let minX = max(first.minX, second.minX)
        let minY = max(first.minY, second.minY)
        let maxX = min(first.maxX, second.maxX)
        let maxY = min(first.maxY, second.maxY)
        guard minX <= maxX, minY <= maxY else { return nil }
        return Rect(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private static func union(_ first: Rect, _ second: Rect) -> Rect {
        assert(first.origin.isFinite && second.origin.isFinite, "A redraw area is not finite")
        return Rect(
            minX: min(first.minX, second.minX),
            minY: min(first.minY, second.minY),
            maxX: max(first.maxX, second.maxX),
            maxY: max(first.maxY, second.maxY)
        )
    }
}
