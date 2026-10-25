import Metal

/// The staging buffers of the preview uploads: one shared buffer of 512 by 512 bytes per frame in
/// flight, reused (PERF-01). A frame packs the new previews into its buffer and copies them into
/// the atlas with one blit.
final class PreviewUploads {
    /// The bytes of one staging buffer: one preview of 512 pixels, or 16 of 128.
    static let capacity = PreviewSlots.sides[0] * PreviewSlots.sides[0]

    private let buffers: [any MTLBuffer]
    private var index = 0
    /// The bytes that the current frame wrote.
    private(set) var used = 0

    /// Makes the buffers.
    ///
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make a buffer.
    init(device: any MTLDevice) throws(RenderingError) {
        var buffers: [any MTLBuffer] = []
        for _ in 0..<DrawListRing.bufferCount {
            guard let buffer = device.makeBuffer(length: Self.capacity, options: .storageModeShared)
            else { throw .resourceUnavailable("preview staging buffer") }
            buffer.label = "Preview uploads"
            buffers.append(buffer)
        }
        self.buffers = buffers
    }

    /// The buffer of the current frame.
    var buffer: any MTLBuffer { buffers[index] }

    /// Makes the next buffer the buffer of the frame. Call it after `DrawListRing.beginFrame`,
    /// which waits until the GPU no longer reads the buffer of that frame.
    func beginFrame() {
        precondition(!buffers.isEmpty, "The uploads hold their buffers")
        index = (index + 1) % buffers.count
        used = 0
    }

    /// Copies `pixels` into the buffer of the frame.
    ///
    /// - Returns: The offset of the pixels, or `nil` if the frame has no room left for them.
    func append(_ pixels: [UInt8]) -> Int? {
        guard used + pixels.count <= Self.capacity else { return nil }
        let offset = used
        write(pixels, at: offset)
        used += pixels.count
        return offset
    }
}
