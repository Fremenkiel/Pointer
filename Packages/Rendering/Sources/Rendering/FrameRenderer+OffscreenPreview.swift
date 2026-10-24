import Geometry
import Metal
import Model

/// The offscreen render of the preview of a canvas that is not on the screen (D-97, D-157).
extension FrameRenderer {
    /// Renders the preview of the items of `content` that touch the region of `placement`, with
    /// the passes of `renderImage`. Cards show their frames and titles without previews. The
    /// strokes draw in passes whose points fit `previewArenaByteBudget`. It blocks until the
    /// GPU completes (m6-plan.md task 3.3, item 6).
    ///
    /// - Precondition: The content keeps the node limit.
    /// - Throws: `RenderingError` if a Metal object fails.
    /// - Returns: The gray image of the placement.
    func renderPreviewImage(
        of content: CanvasContent,
        placement: PreviewRenderer.Placement
    ) throws(RenderingError) -> PreviewImage {
        let nodes = content.cards.count + content.textBoxes.count
        precondition(nodes <= Limits.maxNodesPerCanvas, "Too many nodes: \(nodes)")
        let region = placement.region
        let preview = try offscreenTargets()
        let target = InkTarget(texture: preview.coverage, camera: placement.camera, displayScale: 1)
        let strokes = content.strokes.values.filter { $0.bounds.intersects(region) }
        try encodeStrokePasses(strokes, target: target)
        guard let commandBuffer = resources.queue.makeCommandBuffer() else {
            throw .resourceUnavailable("command buffer")
        }
        let text = try encodeText(
            content.textBoxes.values.filter { Self.mayTouch($0, region) },
            cards: content.cards.values.filter { $0.frame.intersects(region) },
            target: target,
            commandBuffer: commandBuffer,
            region: region
        )
        let size = placement.image.size
        let readback = try encodeReadback(
            of: preview,
            image: placement.image,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        withExtendedLifetime(text) {}
        let image = PreviewRenderer.readImage(of: readback, width: size.width, height: size.height)
        guard let image else { throw .resourceUnavailable("preview readback") }
        return image
    }

    /// Draws `strokes` in passes of one command buffer each, so that the arena of a pass keeps
    /// `previewArenaByteBudget`. The first pass clears the target, also without a stroke. Each
    /// pass waits for the GPU, and its arena goes before the next one comes.
    private func encodeStrokePasses(
        _ strokes: [Stroke],
        target: InkTarget
    ) throws(RenderingError) {
        let passes = PreviewPasses.split(strokes, byteBudget: configuration.previewArenaByteBudget)
        precondition(!passes.isEmpty, "The first pass clears the target")
        for (index, pass) in passes.enumerated() {
            guard let commandBuffer = resources.queue.makeCommandBuffer() else {
                throw .resourceUnavailable("command buffer")
            }
            let ink = try encodeStrokes(
                pass,
                target: target,
                commandBuffer: commandBuffer,
                clear: index == 0
            )
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            withExtendedLifetime(ink) {}
        }
        assert(passes.joined().count == strokes.count, "Each stroke draws in one pass")
    }

    /// The preview targets of the offscreen renders. The first render makes them, and later
    /// renders reuse them. The offscreen renderer never runs the preview jobs of the screen.
    private func offscreenTargets() throws(RenderingError) -> PreviewRenderer {
        if let previewRenderer { return previewRenderer }
        let made = try PreviewRenderer(resources: resources)
        previewRenderer = made
        assert(made.job == nil, "Offscreen targets have no job")
        return made
    }

    /// Returns true if the text of `box` can touch `region`. A box lays out its lines down and
    /// to the right of its origin, at most `TextStyle.maxWidth` wide, so a box that starts
    /// below the region or far to one side stays out. The text store then checks the bounds.
    static func mayTouch(_ box: TextBox, _ region: Rect) -> Bool {
        box.origin.y <= region.maxY && box.origin.x <= region.maxX
            && box.origin.x + TextStyle.maxWidth >= region.minX
    }
}

/// The split of the strokes of an offscreen preview into passes under an arena byte budget.
enum PreviewPasses {
    /// The smallest budget: one stroke of `Limits.maxPointsPerStroke` points fits.
    static var minimumByteBudget: Int { arenaBytes(points: Limits.maxPointsPerStroke) }

    /// Returns the bytes of an arena for `points` points: a block holds at most twice its
    /// points, and each size class can leave one partial slab.
    static func arenaBytes(points: Int) -> Int {
        let slabs = (points * 2) / SlabAllocator.slabPoints + SlabAllocator.classCount + 1
        return slabs * PointArena.bytesPerSlab
    }

    /// Splits `strokes` into passes whose arenas keep `byteBudget`, in their order. Without a
    /// stroke, the result is one empty pass.
    ///
    /// - Precondition: `byteBudget` is at least `minimumByteBudget`.
    static func split(_ strokes: [Stroke], byteBudget: Int) -> [[Stroke]] {
        precondition(byteBudget >= minimumByteBudget, "Budget \(byteBudget) holds no long stroke")
        var passes: [[Stroke]] = [[]]
        var points = 0
        for stroke in strokes {
            let count = stroke.points.count
            if points > 0 && arenaBytes(points: points + count) > byteBudget {
                passes.append([])
                points = 0
            }
            passes[passes.count - 1].append(stroke)
            points += count
        }
        assert(passes.allSatisfy { !$0.isEmpty } || strokes.isEmpty, "No pass is empty")
        return passes
    }
}
