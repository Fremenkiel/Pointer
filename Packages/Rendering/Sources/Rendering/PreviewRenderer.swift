import Geometry
import Metal
import Model

/// Renders the preview of the shown canvas in chunks, so that no frame drops (m6-plan.md
/// section 4, rule 6, D-97, D-98).
///
/// One `.rg8Unorm` target of 512 by 512 pixels and one `.r8Unorm` resolve target of the same
/// size, made at the first leave. Each preview reads its image back through a buffer of its own
/// (m7-plan.md section 6.7). The preview shows
/// the child region of the open camera, cut to the aspect of the card. Cards of the canvas show
/// their frames and titles without previews (architecture.md 5.5).
final class PreviewRenderer {
    /// The side of the targets: the largest preview.
    static let side = PreviewImage.maxSide

    /// One preview in progress.
    struct Job {
        let request: PreviewRenderRequest
        /// The child region of the preview, in canvas space.
        let region: Rect
        let target: InkTarget
        /// The pixel rectangle of the image in the targets.
        let image: MTLRegion
        var inkCursor = 0
        var greenCursor = 0
        var hasCleared = false
    }

    /// The pipelines and the device.
    let resources: InkResources
    /// The coverage target of the preview.
    let coverage: any MTLTexture
    /// The resolve target of the preview.
    let resolved: any MTLTexture
    /// The preview in progress, or `nil`.
    var job: Job?
    /// The strokes of the job. Reused (PERF-01).
    var slots: [Int] = []
    /// The green items of the job. Reused (PERF-01).
    var greens: [GreenItem] = []

    /// Makes the targets.
    ///
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make one of them.
    init(resources: InkResources) throws(RenderingError) {
        self.resources = resources
        coverage = try resources.makeTarget(
            width: Self.side,
            height: Self.side,
            format: InkResources.committedFormat
        )
        resolved = try resources.makeTarget(
            width: Self.side,
            height: Self.side,
            format: InkResources.maskFormat
        )
        assert(resolved.width == Self.side && resolved.height == Self.side, "Targets of one size")
    }

    /// Returns the child region of the open camera, cut to the aspect of the card (D-98): the
    /// card covers a screen of `viewSize` at the scale k = max(W / w, H / h).
    ///
    /// - Precondition: The aspect and the view size are positive.
    static func region(camera: Camera, cardAspect: Double, viewSize: Size) -> Rect {
        precondition(cardAspect > 0 && cardAspect.isFinite, "Card aspect \(cardAspect)")
        precondition(viewSize.width > 0 && viewSize.height > 0, "View size \(viewSize)")
        let width = max(viewSize.width, cardAspect * viewSize.height) / camera.zoom
        let height = max(viewSize.height, viewSize.width / cardAspect) / camera.zoom
        let size = Size(width: width, height: height)
        assert(abs(width / height - cardAspect) < 1e-9 * max(1, cardAspect), "The aspect holds")
        return Rect(origin: camera.center - size.halfDiagonal, size: size)
    }

    /// Where a preview lies: the child region, the camera of the target, and the pixel rectangle
    /// of the image in the targets.
    struct Placement {
        let region: Rect
        let camera: Camera
        let image: MTLRegion
    }

    /// Returns the placement of a preview of `size` pixels on its longer side.
    ///
    /// - Precondition: `size` is from 1 to `side`, and the aspect and the view size are positive.
    static func placement(
        camera: Camera,
        cardAspect: Double,
        size: Int,
        viewSize: Size
    ) -> Placement {
        precondition(size > 0 && size <= side, "Size \(size)")
        let region = Self.region(camera: camera, cardAspect: cardAspect, viewSize: viewSize)
        let wide = cardAspect >= 1
        let width = wide ? size : max(1, Int((Double(size) * cardAspect).rounded()))
        let height = wide ? max(1, Int((Double(size) / cardAspect).rounded())) : size
        let image = MTLRegion(
            origin: MTLOrigin(x: (side - width) / 2, y: (side - height) / 2, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        let zoom = Double(width) / region.size.width
        assert(zoom > 0 && zoom.isFinite, "The target has pixels per canvas point")
        return Placement(
            region: region,
            camera: Camera(center: region.center, zoom: zoom),
            image: image
        )
    }

    /// Moves the job in progress out, so that no frame continues it, or returns `nil` (D-131).
    func takeJob() -> Job? {
        defer { job = nil }
        return job
    }

    /// Starts a job for `request` on a canvas shown in `viewSize`. A job in progress ends with
    /// `nil`, because the newer request wins.
    func start(_ request: PreviewRenderRequest, viewSize: Size) {
        precondition(request.size > 0 && request.size <= Self.side, "Size \(request.size)")
        job?.request.endWithoutImage()
        job = nil
        guard viewSize.width > 0, viewSize.height > 0 else {
            request.endWithoutImage()
            return
        }
        let placement = Self.placement(
            camera: request.camera,
            cardAspect: request.cardAspect,
            size: request.size,
            viewSize: viewSize
        )
        let target = InkTarget(texture: coverage, camera: placement.camera, displayScale: 1)
        job = Job(
            request: request,
            region: placement.region,
            target: target,
            image: placement.image
        )
    }
}
