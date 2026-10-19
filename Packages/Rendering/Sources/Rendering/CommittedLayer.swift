import Geometry
import Metal
import os

/// The committed layer: a texture with all finished ink around the viewport (architecture.md
/// 5.2, D-28).
///
/// The texture covers the viewport plus a margin of half a screen on each side. While the camera
/// moves, the composite pass shows it translated and scaled. A second texture is drawn for the
/// current camera in chunks, one chunk per frame, and replaces the first one when it is complete.
final class CommittedLayer {
    private struct Build {
        let target: InkTarget
        var cursor = 0
        var hasCleared = false
    }

    /// The first capacity of the build list. It grows once to the largest canvas.
    private static let initialSlotCapacity = 4096
    /// The size of a texture over the size of the drawable.
    static let textureScale = 2.0
    /// The zoom ratios, front zoom over camera zoom, that the front texture serves without a
    /// build (docs/m2-fix-plan.md, phase 2).
    static let zoomBand = 0.8...1.25
    /// The part of the margin that the visible rectangle must keep inside the front texture.
    static let marginReserve = 0.25
    /// A camera that stays still for this many frames gets a build at its exact zoom.
    static let stillFramesBeforeExactBuild = 6

    /// The texture with all strokes, or `nil` before the first build completes.
    private(set) var front: InkTarget?
    /// The front texture of the layer before a new viewport, for example a rotation. The screen
    /// shows it, scaled, until the first build completes, so a resize shows no black screen
    /// (docs/m2-fix-plan.md, phase 5, task 6).
    private(set) var fallback: InkTarget?
    private let textures: [any MTLTexture]
    /// The eraser mask: the size of a committed texture, one coverage channel (D-66).
    let mask: any MTLTexture
    /// The drawable width in pixels that the textures were made for.
    let drawableWidth: Int
    /// The drawable height in pixels that the textures were made for.
    let drawableHeight: Int
    private var frontIndex = 1
    private var build: Build?
    private var isStale = false
    /// The camera of the last frame, and the frames in a row with that camera.
    private var lastCamera: Camera?
    private var stillFrames = 0
    /// The strokes of the build, in drawing order. Reused, so a build allocates nothing.
    private var buildSlots: [Int] = []
    /// The strokes of a redraw. Reused like `buildSlots`.
    private var redrawSlots: [Int] = []
    /// The pixels around a changed area that the redraw clears too: the anti-aliased edge of
    /// the ink (`InkEncoder.edgeHalfWidthPixels`) and one pixel for the rounding.
    static let redrawMarginPixels = 3.0

    /// Makes the two textures for a drawable size.
    ///
    /// - Precondition: The drawable size is positive.
    /// - Throws: `RenderingError` if Metal cannot make the textures.
    init(
        resources: InkResources,
        drawableWidth: Int,
        drawableHeight: Int,
        fallback: InkTarget? = nil
    ) throws(RenderingError) {
        precondition(drawableWidth > 0 && drawableHeight > 0, "Drawable size must be positive")
        let width = Int((Double(drawableWidth) * Self.textureScale).rounded(.up))
        let height = Int((Double(drawableHeight) * Self.textureScale).rounded(.up))
        let format = InkResources.committedFormat
        textures = [
            try resources.makeTarget(width: width, height: height, format: format),
            try resources.makeTarget(width: width, height: height, format: format),
        ]
        mask = try resources.makeTarget(width: width, height: height, format: format)
        self.drawableWidth = drawableWidth
        self.drawableHeight = drawableHeight
        self.fallback = fallback
        buildSlots.reserveCapacity(Self.initialSlotCapacity)
        assert(textures.count == 2, "The layer alternates two textures")
    }

    /// `true` while a build has strokes left to draw.
    var isBuilding: Bool { build != nil }

    /// `true` while the front texture shows another camera than the last frame. The renderer then
    /// keeps drawing frames until the exact build after the camera stops.
    var isSettling: Bool {
        guard let front, let lastCamera else { return false }
        return front.camera != lastCamera
    }

    /// Starts a build for `camera` if no build runs and the front texture needs one. Call it once
    /// per frame, because it counts the frames with a still camera.
    ///
    /// A build starts in these cases: no front texture exists, a load made the front texture
    /// old, the zoom ratio leaves `zoomBand`, the visible rectangle leaves the front texture
    /// minus a quarter of its margin, or the camera stays still for
    /// `stillFramesBeforeExactBuild` frames away from the front camera.
    ///
    /// - Precondition: `displayScale` is positive.
    /// - Returns: `true` if a build started.
    func startBuildIfNeeded(camera: Camera, displayScale: Double, store: StrokeStore) -> Bool {
        precondition(displayScale > 0, "Display scale must be positive, got \(displayScale)")
        RenderSignpost.begin("StartBuildIfNeeded")
        defer { RenderSignpost.end("StartBuildIfNeeded") }
        stillFrames = camera == lastCamera ? stillFrames + 1 : 0
        lastCamera = camera
        guard build == nil, needsBuild(camera: camera, displayScale: displayScale) else {
            return false
        }
        isStale = false
        let texture = textures[1 - frontIndex]
        let target = InkTarget(texture: texture, camera: camera, displayScale: displayScale)
        buildSlots.removeAll(keepingCapacity: true)
        store.grid.forEachItem(touching: target.canvasRect) { buildSlots.append($0) }
        build = Build(target: target)
        assert(front?.texture !== texture, "A build never draws into the front texture")
        return true
    }

    private func needsBuild(camera: Camera, displayScale: Double) -> Bool {
        guard let front, !isStale, front.displayScale == displayScale else { return true }
        guard front.camera != camera else { return false }
        guard Self.zoomBand.contains(front.camera.zoom / camera.zoom) else { return true }
        guard covers(front, camera: camera) else { return true }
        return stillFrames >= Self.stillFramesBeforeExactBuild
    }

    /// Returns `true` if the front texture, minus a quarter of its margin, holds the visible
    /// rectangle of `camera`.
    private func covers(_ front: InkTarget, camera: Camera) -> Bool {
        let scale = front.displayScale
        let viewSize = Size(
            width: Double(drawableWidth) / scale,
            height: Double(drawableHeight) / scale
        )
        let visible = camera.visibleRect(viewSize: viewSize)
        let texture = front.canvasRect
        let pixels = front.pixelsPerCanvasPoint
        let reserveX = Double(front.texture.width - drawableWidth) / 2 / pixels * Self.marginReserve
        let reserveY =
            Double(front.texture.height - drawableHeight) / 2 / pixels * Self.marginReserve
        assert(reserveX >= 0 && reserveY >= 0, "The texture is smaller than the drawable")
        return visible.minX >= texture.minX + reserveX && visible.maxX <= texture.maxX - reserveX
            && visible.minY >= texture.minY + reserveY && visible.maxY <= texture.maxY - reserveY
    }

    /// Marks the front texture as old after a change that is not one new stroke, for example a
    /// load. The screen keeps it until a new build completes. A running build starts again.
    func invalidate() {
        isStale = true
        build = nil
    }

    /// Adds a stroke to a running build only, for a stroke whose ink is on the front texture
    /// already, as the parts of an erase.
    func addToBuild(_ slot: Int) {
        precondition(slot >= 0, "Stroke slot \(slot) is invalid")
        if build != nil { buildSlots.append(slot) }
    }

    /// Adds the new strokes of a frame: it draws them into the front texture in one pass and adds
    /// them to a running build. A full draw list continues the strokes in another pass.
    ///
    /// - Precondition: The slots are strokes of the store.
    func addStrokes(
        _ slots: [Int],
        encoder: InkEncoder,
        context: FrameContext
    ) {
        precondition(slots.allSatisfy { $0 >= 0 }, "A stroke slot is invalid")
        if build != nil {
            buildSlots.append(contentsOf: slots)
        }
        guard let front, !slots.isEmpty else { return }
        let options = InkPassOptions(clear: false, instanceBudget: .max)
        var cursor = 0
        for _ in slots.indices where cursor < slots.count {
            cursor = encoder.encodePass(
                context,
                target: front,
                slots: slots,
                cursor: cursor,
                options: options
            )
        }
        assert(cursor == slots.count, "The handoff passes draw each new stroke")
    }

    /// Clears a canvas area in the front texture and in a running build, and draws the strokes
    /// of the store there again (architecture.md 5.2, D-66).
    ///
    /// The ink blends with `max`, so a removed stroke cannot be subtracted. A build that has not
    /// drawn yet needs nothing, because it skips the removed strokes.
    ///
    /// - Precondition: `area` is finite.
    func redraw(_ area: Rect, store: StrokeStore, encoder: InkEncoder, context: FrameContext) {
        precondition(area.origin.isFinite, "Redraw area is not finite")
        RenderSignpost.begin("Redraw")
        defer { RenderSignpost.end("Redraw") }
        var targets: [InkTarget] = []
        if let front { targets.append(front) }
        if let build, build.hasCleared { targets.append(build.target) }
        for target in targets {
            guard let scissor = Self.scissor(for: area, in: target) else { continue }
            let margin = Self.redrawMarginPixels / target.pixelsPerCanvasPoint
            redrawSlots.removeAll(keepingCapacity: true)
            store.grid.forEachItem(touching: area.expanded(by: margin)) { redrawSlots.append($0) }
            var options = InkPassOptions(clear: false, instanceBudget: .max)
            options.scissor = scissor
            options.clearsScissor = true
            options.clip = area.expanded(by: margin)
            var cursor = 0
            // Each pass draws one stroke at least, so the loop ends. A full draw list ends a pass.
            // The first pass runs also without strokes, because it clears the area.
            let passLimit = redrawSlots.count + 1
            for _ in 0..<passLimit where cursor < redrawSlots.count || options.clearsScissor {
                cursor = encoder.encodePass(
                    context,
                    target: target,
                    slots: redrawSlots,
                    cursor: cursor,
                    options: options
                )
                options.clearsScissor = false
            }
            assert(cursor == redrawSlots.count, "The redraw drew each stroke of the area")
        }
    }

    /// Returns the pixel rectangle of a canvas area in a target, with the redraw margin, or `nil`
    /// if the area lies outside the target.
    static func scissor(for area: Rect, in target: InkTarget) -> MTLScissorRect? {
        let pixels = target.pixelsPerCanvasPoint
        let texture = target.canvasRect
        let minX = ((area.minX - texture.minX) * pixels - redrawMarginPixels).rounded(.down)
        let minY = ((area.minY - texture.minY) * pixels - redrawMarginPixels).rounded(.down)
        let maxX = ((area.maxX - texture.minX) * pixels + redrawMarginPixels).rounded(.up)
        let maxY = ((area.maxY - texture.minY) * pixels + redrawMarginPixels).rounded(.up)
        let width = Double(target.texture.width)
        let height = Double(target.texture.height)
        let low = (x: min(max(minX, 0), width), y: min(max(minY, 0), height))
        let high = (x: min(max(maxX, 0), width), y: min(max(maxY, 0), height))
        guard high.x > low.x, high.y > low.y else { return nil }
        assert(low.x >= 0 && low.y >= 0, "Scissor starts outside the texture")
        return MTLScissorRect(
            x: Int(low.x),
            y: Int(low.y),
            width: Int(high.x - low.x),
            height: Int(high.y - low.y)
        )
    }

    /// Draws the next chunk of the build. A complete build becomes the front texture.
    ///
    /// - Precondition: `budget` is positive.
    func continueBuild(
        encoder: InkEncoder,
        context: FrameContext,
        budget: Int,
        deadline: TimeInterval = .infinity
    ) {
        precondition(budget > 0, "Build budget must be positive, got \(budget)")
        guard var current = build else { return }
        RenderSignpost.begin("ContinueBuild")
        defer { RenderSignpost.end("ContinueBuild") }
        let options = InkPassOptions(
            clear: !current.hasCleared,
            instanceBudget: budget,
            deadline: deadline
        )
        current.cursor = encoder.encodePass(
            context,
            target: current.target,
            slots: buildSlots,
            cursor: current.cursor,
            options: options
        )
        current.hasCleared = true
        guard current.cursor >= buildSlots.count else {
            build = current
            return
        }
        frontIndex = 1 - frontIndex
        front = current.target
        fallback = nil
        build = nil
        assert(front?.texture === textures[frontIndex], "The front index follows the front texture")
    }

    /// The texture that the screen shows: the front texture, or the fallback before the first
    /// build completes.
    var shown: InkTarget? { front ?? fallback }

    /// Returns the composite values that show the shown texture with `camera`.
    ///
    /// A drawable pixel p shows the texture pixel `p * scale + offset`.
    ///
    /// - Precondition: A texture is shown, and `displayScale` is positive.
    func compositeUniforms(
        camera: Camera,
        displayScale: Double,
        drawableSize: Size
    ) -> CompositeUniforms {
        precondition(displayScale > 0, "Display scale must be positive, got \(displayScale)")
        guard let front = shown else { preconditionFailure("No texture to composite") }
        // Texture pixels per drawable pixel. A fallback can have another display scale.
        let ratio = front.pixelsPerCanvasPoint / (camera.zoom * displayScale)
        let pixelsPerPoint = front.pixelsPerCanvasPoint
        let shift = camera.center - front.camera.center
        let size = front.pixelSize
        var offsetX = size.width / 2 + shift.dx * pixelsPerPoint - ratio * drawableSize.width / 2
        var offsetY = size.height / 2 + shift.dy * pixelsPerPoint - ratio * drawableSize.height / 2
        assert(offsetX.isFinite && offsetY.isFinite, "Composite offset is not finite")
        // At a ratio of 1, a whole-pixel offset maps each drawable pixel to one texture pixel, so
        // the linear filter does not blur the ink during a pan (docs/m2-fix-plan.md, phase 5).
        if ratio == 1 {
            offsetX.round()
            offsetY.round()
        }
        return CompositeUniforms(
            scale: SIMD2(Float(ratio), Float(ratio)),
            offset: SIMD2(Float(offsetX), Float(offsetY)),
            textureSize: SIMD2(Float(size.width), Float(size.height))
        )
    }
}
