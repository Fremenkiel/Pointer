import Geometry
import Metal
import Model

/// The eraser circles of one gesture in the mask texture of the committed layer (architecture.md
/// 5.2, D-66).
///
/// The eraser tool sends each sample while the pencil moves. Each frame stamps the new samples
/// into the mask, as capsules from the sample before, so a fast pencil leaves no gap. The mask
/// uses the mapping of the front texture. If the front texture changes during the gesture, the
/// next frame clears the mask and stamps all samples again.
struct EraserMask {
    /// The most samples of one gesture, the bound of `EraserPath.maxSamples`.
    static let maxSamples = Limits.maxPointsPerStroke

    /// `true` from the start to the end of a gesture.
    private(set) var isActive = false
    /// The eraser radius in canvas units.
    private var radius = 0.0
    /// The samples of the gesture in canvas space.
    private var samples: [Point] = []
    /// The number of samples in the mask.
    private var stampedCount = 0
    /// The texture and the camera that the stamps use, or `nil` if the mask is empty.
    private var stampedFor: (texture: ObjectIdentifier, camera: Camera)?
    /// The stamp pass, made once (PERF-01).
    private let pass: MTLRenderPassDescriptor = {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        return pass
    }()

    /// `true` if the mask holds stamps that the composite pass must use.
    var hasStamps: Bool { isActive && stampedCount > 0 }

    /// `true` if samples wait for a frame.
    var hasNewSamples: Bool { isActive && stampedCount < samples.count }

    /// Starts a gesture with a radius in canvas units.
    ///
    /// - Precondition: `radius` is positive and finite.
    mutating func begin(radius: Double) {
        precondition(radius > 0 && radius.isFinite, "Eraser radius must be positive, got \(radius)")
        // Room for the longest gesture once, so a sample never grows the list on the render
        // thread (M-07). The list keeps it for the next gestures.
        if samples.capacity < Self.maxSamples {
            samples.reserveCapacity(Self.maxSamples)
        }
        samples.removeAll(keepingCapacity: true)
        self.radius = radius
        stampedCount = 0
        stampedFor = nil
        isActive = true
    }

    /// Adds a sample in canvas space. A sample outside a gesture or past `maxSamples` is
    /// ignored.
    mutating func append(_ point: Point) {
        guard isActive, samples.count < Self.maxSamples, point.isFinite else { return }
        samples.append(point)
        assert(samples.count <= Self.maxSamples, "Too many eraser samples")
    }

    /// Ends the gesture. The composite pass stops to use the mask.
    mutating func end() {
        isActive = false
        samples.removeAll(keepingCapacity: true)
        stampedCount = 0
        stampedFor = nil
        assert(!hasStamps, "An ended gesture has no stamps")
    }

    /// Stamps the new samples into `mask`, with the mapping of `front`.
    ///
    /// - Precondition: `mask` has the size of the front texture.
    mutating func encode(
        into mask: any MTLTexture,
        front: InkTarget,
        resources: InkResources,
        commandBuffer: any MTLCommandBuffer
    ) {
        precondition(
            mask.width == front.texture.width && mask.height == front.texture.height,
            "The mask has the size of the committed texture"
        )
        let target = (ObjectIdentifier(front.texture), front.camera)
        let isSameTarget = stampedFor.map { $0.texture == target.0 && $0.camera == target.1 }
        let first = isSameTarget == true ? stampedCount : 0
        guard isActive, first < samples.count else { return }
        pass.colorAttachments[0].texture = mask
        pass.colorAttachments[0].loadAction = first == 0 ? .clear : .load
        let made = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        // The descriptor lives on, so it must not hold the texture after the pass.
        pass.colorAttachments[0].texture = nil
        guard let encoder = made else {
            assertionFailure("Metal gave no render encoder for the eraser mask")
            return
        }
        encoder.setRenderPipelineState(resources.eraserPipeline)
        for index in first..<samples.count {
            let stamp = makeStamp(index, front: front)
            encoder.setVertexValue(stamp, index: 0)
            encoder.setFragmentValue(stamp, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        stampedCount = samples.count
        stampedFor = target
        assert(hasStamps, "The mask holds the stamps of the gesture")
    }

    /// Returns the capsule from the sample before `index` to `index` in mask pixels.
    private func makeStamp(_ index: Int, front: InkTarget) -> EraserStamp {
        precondition(samples.indices.contains(index), "Eraser sample \(index) does not exist")
        let rect = front.canvasRect
        let pixels = front.pixelsPerCanvasPoint
        func pixel(_ point: Point) -> SIMD2<Float> {
            SIMD2(Float((point.x - rect.minX) * pixels), Float((point.y - rect.minY) * pixels))
        }
        let size = front.pixelSize
        assert(pixels > 0, "A target has a positive scale")
        return EraserStamp(
            start: pixel(samples[max(index - 1, 0)]),
            end: pixel(samples[index]),
            targetSize: SIMD2(Float(size.width), Float(size.height)),
            radius: Float(radius * pixels),
            edge: InkEncoder.edgeHalfWidthPixels
        )
    }
}
