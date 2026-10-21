import Geometry
import Metal
import Model

/// Renders the preview of the shown canvas in chunks, so that no frame drops (m6-plan.md
/// section 4, rule 6, D-97, D-98).
///
/// One `.rg8Unorm` target of 512 by 512 pixels and one `.r8Unorm` resolve target of the same
/// size, made at the first leave, and one shared readback buffer of 256 KB. The preview shows
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
    let coverage: any MTLTexture
    let resolved: any MTLTexture
    let readback: any MTLBuffer
    /// The preview in progress, or `nil`.
    var job: Job?
    /// The strokes and the green items of the job. Reused (PERF-01).
    var slots: [Int] = []
    var greens: [GreenItem] = []

    /// Makes the targets and the readback buffer.
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
        guard
            let buffer = resources.device.makeBuffer(
                length: Self.side * Self.side,
                options: .storageModeShared
            )
        else { throw .resourceUnavailable("preview readback buffer") }
        buffer.label = "Preview readback"
        readback = buffer
        assert(readback.length == Self.side * Self.side, "One byte per pixel")
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

    /// Starts a job for `request` on a canvas shown in `viewSize`. A job in progress ends with
    /// `nil`, because the newer request wins.
    func start(_ request: PreviewRenderRequest, viewSize: Size) {
        precondition(request.size > 0 && request.size <= Self.side, "Size \(request.size)")
        job?.request.completion(nil)
        job = nil
        guard viewSize.width > 0, viewSize.height > 0 else {
            request.completion(nil)
            return
        }
        let region = Self.region(
            camera: request.camera,
            cardAspect: request.cardAspect,
            viewSize: viewSize
        )
        let wide = request.cardAspect >= 1
        let size = Double(request.size)
        let width = wide ? request.size : max(1, Int((size * request.cardAspect).rounded()))
        let height = wide ? max(1, Int((size / request.cardAspect).rounded())) : request.size
        let pixels = Double(width) / region.size.width
        let target = InkTarget(
            texture: coverage,
            camera: Camera(center: region.center, zoom: pixels),
            displayScale: 1
        )
        let image = MTLRegion(
            origin: MTLOrigin(x: (Self.side - width) / 2, y: (Self.side - height) / 2, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        job = Job(request: request, region: region, target: target, image: image)
        assert(job != nil, "A request starts a job")
    }
}
