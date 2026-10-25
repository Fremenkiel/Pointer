import Metal

/// Three glyph buffers that frames use in turn, as the draw lists do (PERF-01).
///
/// The ring moves to its next buffer in `beginFrame`. `DrawListRing.beginFrame` waits for a free
/// draw list in the same frame, so the GPU no longer reads the glyph buffer of that frame.
final class GlyphRing {
    /// The glyph quads per buffer.
    let capacity: Int
    private let buffers: [any MTLBuffer]
    private var index = 0
    /// The glyph quads that the current frame wrote.
    private(set) var used = 0

    /// Makes the ring.
    ///
    /// - Precondition: `capacity` is positive.
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make a buffer.
    init(device: any MTLDevice, capacity: Int) throws(RenderingError) {
        precondition(capacity > 0, "Glyph capacity must be positive, got \(capacity)")
        var buffers: [any MTLBuffer] = []
        for _ in 0..<DrawListRing.bufferCount {
            let length = capacity * MemoryLayout<GlyphInstance>.stride
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
                throw .resourceUnavailable("glyph buffer of \(capacity) quads")
            }
            buffer.label = "Glyphs"
            buffers.append(buffer)
        }
        self.capacity = capacity
        self.buffers = buffers
    }

    /// The buffer of the current frame.
    var buffer: any MTLBuffer { buffers[index] }

    /// The glyph quads that the current frame can still write.
    var remaining: Int { capacity - used }

    /// Makes the next buffer the buffer of the frame. Call it after `DrawListRing.beginFrame`.
    func beginFrame() {
        precondition(!buffers.isEmpty, "The ring holds its buffers")
        index = (index + 1) % DrawListRing.bufferCount
        used = 0
    }

    /// Writes glyph quads at the end of the current frame in one copy.
    ///
    /// - Precondition: The frame has room for the quads.
    func append(contentsOf glyphs: [GlyphInstance]) {
        precondition(used + glyphs.count <= capacity, "Glyph buffer is full at \(capacity) quads")
        write(glyphs, at: used)
        used += glyphs.count
    }
}
