import Geometry
import Metal
import Model

/// The text of the committed layer: the text part of a build and the redraw of a text change
/// (architecture.md 5.4, D-82). The text lives in the green channel, so the ink passes and the
/// eraser mask leave it as it is.
extension CommittedLayer {
    /// The redraw of the text of an area in the front texture. A full glyph buffer leaves the
    /// other boxes for the next frame.
    struct TextRedraw {
        let target: InkTarget
        let scissor: MTLScissorRect
        var cursor = 0
        var hasCleared = false
    }

    /// `true` while a text redraw has boxes left for the next frames.
    var isRedrawingText: Bool { textRedraw != nil }

    /// Lists the text boxes that touch a target, for a build.
    func listText(of target: InkTarget, from texts: TextStore?) {
        buildTextIDs.removeAll(keepingCapacity: true)
        texts?.grid.forEachItem(touching: target.canvasRect) { buildTextIDs.append($0) }
    }

    /// Draws the next boxes of the text part of a build.
    ///
    /// - Returns: `true` if the text part is done.
    func continueText(
        of build: inout Build,
        _ text: TextEncoder?,
        _ context: FrameContext,
        deadline: TimeInterval = .infinity
    ) -> Bool {
        guard let text, build.textCursor < buildTextIDs.count || build.clearsText else {
            return true
        }
        var options = TextEncoder.Options()
        options.deadline = deadline
        if build.clearsText {
            options.scissor = Self.wholeScissor(of: build.target)
            options.clearsScissor = true
            build.clearsText = false
        }
        precondition(build.textCursor <= buildTextIDs.count, "The text cursor is in the list")
        build.textCursor = text.encodePass(
            context,
            target: build.target,
            ids: buildTextIDs,
            cursor: build.textCursor,
            options: options
        )
        assert(build.textCursor <= buildTextIDs.count, "The text cursor stays in the list")
        return build.textCursor >= buildTextIDs.count
    }

    /// Notes a change of the text boxes in `area`. The front texture redraws the text of the
    /// area, and a running build lists its text again (D-82).
    ///
    /// - Precondition: `area` is finite.
    func textChanged(_ area: Rect, texts: TextStore) {
        precondition(area.origin.isFinite, "Text area is not finite")
        if var current = build {
            current.clearsText = current.textCursor > 0
            current.textCursor = 0
            listText(of: current.target, from: texts)
            build = current
        }
        let whole = textRedrawArea.map { Self.joined($0, area) } ?? area
        textRedrawArea = whole
        guard let front, let scissor = Self.scissor(for: whole, in: front) else {
            textRedraw = nil
            textRedrawArea = nil
            return
        }
        textRedrawIDs.removeAll(keepingCapacity: true)
        let margin = Self.redrawMarginPixels / front.pixelsPerCanvasPoint
        texts.grid.forEachItem(touching: whole.expanded(by: margin)) { textRedrawIDs.append($0) }
        textRedraw = TextRedraw(target: front, scissor: scissor)
        assert(textRedraw != nil, "A change in the front texture starts a redraw")
    }

    /// Draws the boxes of a running text redraw until the glyph buffer is full. The first pass
    /// clears the text of the area.
    func continueTextRedraw(text: TextEncoder, context: FrameContext) {
        guard var redraw = textRedraw else { return }
        guard let front, front.texture === redraw.target.texture,
            front.camera == redraw.target.camera
        else {
            textRedraw = nil
            textRedrawArea = nil
            return
        }
        precondition(redraw.cursor <= textRedrawIDs.count, "The redraw cursor is in the list")
        var options = TextEncoder.Options(scissor: redraw.scissor)
        options.clearsScissor = !redraw.hasCleared
        redraw.cursor = text.encodePass(
            context,
            target: redraw.target,
            ids: textRedrawIDs,
            cursor: redraw.cursor,
            options: options
        )
        redraw.hasCleared = true
        let isDone = redraw.cursor >= textRedrawIDs.count
        textRedraw = isDone ? nil : redraw
        if isDone { textRedrawArea = nil }
        assert(isDone == (textRedraw == nil), "A done text redraw ends")
    }

    private static func joined(_ first: Rect, _ second: Rect) -> Rect {
        Rect(
            minX: min(first.minX, second.minX),
            minY: min(first.minY, second.minY),
            maxX: max(first.maxX, second.maxX),
            maxY: max(first.maxY, second.maxY)
        )
    }

    /// The scissor of a whole target.
    private static func wholeScissor(of target: InkTarget) -> MTLScissorRect {
        MTLScissorRect(x: 0, y: 0, width: target.texture.width, height: target.texture.height)
    }
}
