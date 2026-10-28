import Dispatch
import Metal
import os

/// Three draw-list buffers that frames use in turn, so the CPU never writes a buffer that the
/// GPU still reads (PERF-01: no allocation per frame).
final class DrawListRing {
    /// The number of buffers, so at most three frames wait for the GPU. With three drawables
    /// (D-41), the pan of the benchmark ran at 120 Hz with this count.
    static let bufferCount = 3

    /// The entries per buffer.
    let capacity: Int
    private let buffers: [any MTLBuffer]
    private let available = DispatchSemaphore(value: bufferCount)
    private var index = 0
    /// Frees a buffer when the GPU completes its frame, and emits the GPU time of the frame as
    /// the signpost event `GPUFrame` (PERF-03). It is the one completed handler of a frame and is
    /// made once, because each handler and each new closure costs an allocation (PERF-01).
    private let release: @Sendable (any MTLCommandBuffer) -> Void
    /// The entries that the current frame wrote.
    private(set) var used = 0

    /// Makes the ring.
    ///
    /// - Precondition: `capacity` is positive.
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make a buffer.
    init(device: any MTLDevice, capacity: Int) throws(RenderingError) {
        precondition(capacity > 0, "Draw list capacity must be positive, got \(capacity)")
        var buffers: [any MTLBuffer] = []
        for _ in 0..<Self.bufferCount {
            let length = capacity * MemoryLayout<StrokeDrawEntry>.stride
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
                throw .resourceUnavailable("draw list of \(capacity) entries")
            }
            buffer.label = "Draw list"
            buffers.append(buffer)
        }
        self.capacity = capacity
        self.buffers = buffers
        let available = available
        let signposter = OSSignposter(subsystem: "dk.saarikivi.pointer", category: "Rendering")
        release = { buffer in
            available.signal()
            // The message with its argument is built only while a tool records (PERF-01,
            // review of 2026-10-28).
            guard signposter.isEnabled else { return }
            let milliseconds = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            signposter.emitEvent("GPUFrame", "\(milliseconds, format: .fixed(precision: 2)) ms")
        }
    }

    /// The buffer of the current frame.
    var buffer: any MTLBuffer { buffers[index] }

    /// The number of entries that the current frame can still write.
    var remaining: Int { capacity - used }

    /// Waits for a free buffer and makes it the buffer of the next frame. The command buffer of
    /// the frame frees it when the GPU completes.
    ///
    /// - Precondition: The command buffer is not committed.
    func beginFrame(_ commandBuffer: any MTLCommandBuffer) {
        precondition(
            commandBuffer.status == .notEnqueued,
            "The frame command buffer is already sent"
        )
        RenderSignpost.begin("BeginFrame")
        available.wait()
        RenderSignpost.end("BeginFrame")
        index = (index + 1) % Self.bufferCount
        used = 0
        assert(
            buffer.length >= capacity * MemoryLayout<StrokeDrawEntry>.stride,
            "Draw list is short"
        )
        commandBuffer.whenCompleted(release)
    }

    /// Writes entries at the end of the current frame in one copy.
    ///
    /// - Precondition: The frame has room for the entries.
    func append(contentsOf entries: [StrokeDrawEntry]) {
        precondition(used + entries.count <= capacity, "Draw list is full at \(capacity) entries")
        write(entries, at: used)
        used += entries.count
    }
}
