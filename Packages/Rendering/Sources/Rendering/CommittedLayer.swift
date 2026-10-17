import Geometry
import Metal

/// The committed layer: a texture with all finished ink around the viewport (architecture.md
/// 5.2, D-28).
///
/// The texture covers the viewport plus a margin of half a screen on each side. While the camera
/// moves, the composite pass shows it translated and scaled. A second texture is drawn for the
/// current camera in chunks, one chunk per frame, and replaces the first one when it is complete.
@MainActor
final class CommittedLayer {
    private struct Build {
        let target: InkTarget
        var cursor = 0
        var hasCleared = false
    }

    /// The first capacity of the build list. It grows once to the largest canvas.
    private static let initialSlotCapacity = 4096

    /// The texture that the screen shows, or `nil` before the first build completes.
    private(set) var front: InkTarget?
    private let textures: [any MTLTexture]
    private var frontIndex = 1
    private var build: Build?
    private var isStale = false
    /// The strokes of the build, in drawing order. Reused, so a build allocates nothing.
    private var buildSlots: [Int] = []

    /// Makes the two textures for a drawable size.
    ///
    /// - Precondition: The drawable size is positive.
    /// - Throws: `RenderingError` if Metal cannot make the textures.
    init(resources: InkResources, drawableWidth: Int, drawableHeight: Int) throws(RenderingError) {
        precondition(drawableWidth > 0 && drawableHeight > 0, "Drawable size must be positive")
        let width = drawableWidth * 2
        let height = drawableHeight * 2
        let format = InkResources.committedFormat
        textures = [
            try resources.makeTarget(width: width, height: height, format: format),
            try resources.makeTarget(width: width, height: height, format: format),
        ]
        buildSlots.reserveCapacity(Self.initialSlotCapacity)
        assert(textures.count == 2, "The layer alternates two textures")
    }

    /// `true` while a build has strokes left to draw.
    var isBuilding: Bool { build != nil }

    /// Starts a build for `camera` if no build runs and the front texture is old.
    ///
    /// - Precondition: `displayScale` is positive.
    /// - Returns: `true` if a build started.
    func startBuildIfNeeded(camera: Camera, displayScale: Double, store: StrokeStore) -> Bool {
        precondition(displayScale > 0, "Display scale must be positive, got \(displayScale)")
        let isCurrent = front?.camera == camera && front?.displayScale == displayScale && !isStale
        guard build == nil, !isCurrent else { return false }
        isStale = false
        let texture = textures[1 - frontIndex]
        let target = InkTarget(texture: texture, camera: camera, displayScale: displayScale)
        buildSlots.removeAll(keepingCapacity: true)
        store.grid.forEachItem(touching: target.canvasRect) { buildSlots.append($0) }
        build = Build(target: target)
        assert(front?.texture !== texture, "A build never draws into the front texture")
        return true
    }

    /// Marks the front texture as old after a change that is not one new stroke, for example a
    /// load. The screen keeps it until a new build completes. A running build starts again.
    func invalidate() {
        isStale = true
        build = nil
    }

    /// Adds a new stroke: it draws it into the front texture now and adds it to a running build.
    ///
    /// - Precondition: `slot` is a stroke of the store.
    func addStroke(
        _ slot: Int,
        encoder: InkEncoder,
        commandBuffer: any MTLCommandBuffer,
        frame: UInt64
    ) {
        precondition(slot >= 0, "Stroke slot \(slot) is invalid")
        if build != nil {
            buildSlots.append(slot)
        }
        guard let front else { return }
        let options = InkPassOptions(clear: false, instanceBudget: .max, frame: frame)
        let cursor = encoder.encodePass(
            commandBuffer,
            target: front,
            slots: [slot],
            cursor: 0,
            options: options
        )
        assert(cursor == 1, "The handoff pass draws its one stroke")
    }

    /// Draws the next chunk of the build. A complete build becomes the front texture.
    ///
    /// - Precondition: `budget` is positive.
    func continueBuild(
        encoder: InkEncoder,
        commandBuffer: any MTLCommandBuffer,
        budget: Int,
        frame: UInt64,
        deadline: TimeInterval = .infinity
    ) {
        precondition(budget > 0, "Build budget must be positive, got \(budget)")
        guard var current = build else { return }
        let options = InkPassOptions(
            clear: !current.hasCleared,
            instanceBudget: budget,
            frame: frame,
            deadline: deadline
        )
        current.cursor = encoder.encodePass(
            commandBuffer,
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
        build = nil
        assert(front?.texture === textures[frontIndex], "The front index follows the front texture")
    }

    /// Returns the composite values that show the front texture with `camera`.
    ///
    /// A drawable pixel p shows the texture pixel `p * scale + offset`. Both textures use the
    /// same display scale, so the zoom ratio is the scale.
    ///
    /// - Precondition: A front texture exists.
    func compositeUniforms(camera: Camera, drawableSize: Size) -> CompositeUniforms {
        guard let front else { preconditionFailure("No front texture to composite") }
        let ratio = front.camera.zoom / camera.zoom
        let pixelsPerPoint = front.pixelsPerCanvasPoint
        let shift = camera.center - front.camera.center
        let size = front.pixelSize
        let offsetX = size.width / 2 + shift.dx * pixelsPerPoint - ratio * drawableSize.width / 2
        let offsetY = size.height / 2 + shift.dy * pixelsPerPoint - ratio * drawableSize.height / 2
        assert(offsetX.isFinite && offsetY.isFinite, "Composite offset is not finite")
        return CompositeUniforms(
            scale: SIMD2(Float(ratio), Float(ratio)),
            offset: SIMD2(Float(offsetX), Float(offsetY)),
            textureSize: SIMD2(Float(size.width), Float(size.height))
        )
    }
}
