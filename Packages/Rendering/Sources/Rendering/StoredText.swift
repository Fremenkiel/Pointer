import Metal
import Model

/// The stored glyph runs of a text encoder and the record buffers of their draws (architecture.md
/// 5.4.1, D-94, D-190).
///
/// A pass writes one `GlyphRecord` per box into the record buffer of the frame. The vertex
/// shader of the paged glyph draw turns the records into quads. The record buffers start at the
/// first pass with records and grow with the passes, so that a canvas with little text holds
/// little memory.
final class StoredText {
    /// The quads that one record buffer holds at most: two passes over the node limit.
    static let recordCapacity = 2 * Limits.maxNodesPerCanvas
    /// The time in seconds that the passes of one frame can spend on the builds of new runs, the
    /// build budget of a frame (D-105). A pass without a deadline, as the redraw of an edit, had
    /// the glyph buffer of the frame as its bound, and the stored quads of a frame are four
    /// times as many.
    static let buildBudget = 0.002
    /// The pass reads the clock once per this number of builds.
    static let buildCheckInterval = 4
    /// The fewest glyphs of a layout that takes a stored run. A pass with stored runs added an
    /// expansion pass, which cost 0.09 ms of GPU time in a pan over the cards at zoom 1 (+14 %),
    /// where each pass held card titles only (D-190 moved the expansion into the draw). A title
    /// holds at most `Limits.maxTitleLength` code points, so titles and short boxes take the CPU
    /// path, which writes them in a few microseconds.
    static let minimumGlyphs = 128

    /// The smallest record buffer.
    static let initialRecords = 1_024

    private let device: any MTLDevice
    /// The stored runs.
    let runs: GlyphRunStore
    /// The stored quads that the passes of one frame draw at most.
    let capacity: Int
    /// The record buffer of each frame in flight, or `nil` before its first records.
    private var recordBuffers: [(any MTLBuffer)?]
    private var recordIndex = 0
    /// The stored quads that the earlier passes of the frame drew.
    private(set) var used = 0
    /// The records that the earlier passes of the frame wrote.
    private(set) var recordsUsed = 0
    /// The records of the current pass, reused (PERF-01).
    var records: [GlyphRecord] = []
    /// The quads of the records of the current pass.
    private(set) var passQuads = 0
    /// The quads of the run that a build writes, reused.
    var quads: [StoredGlyph] = []
    /// The pages and their generations of the run that a build writes, reused.
    var pages: [Int] = []
    var generations: [UInt32] = []
    /// The `CACurrentMediaTime()` value after which the current pass builds no new run.
    private(set) var buildDeadline: TimeInterval = .infinity
    /// The `CACurrentMediaTime()` value after which no pass of the frame builds a new run.
    private var frameBuildDeadline: TimeInterval = .infinity
    /// The runs that the current pass built.
    private(set) var passBuilds = 0

    /// Makes the buffers.
    ///
    /// - Precondition: `capacity` is positive.
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make a buffer.
    init(device: any MTLDevice, capacity: Int, runByteBudget: Int) throws(RenderingError) {
        precondition(capacity > 0, "A frame draws stored quads, got \(capacity)")
        self.device = device
        self.capacity = capacity
        recordBuffers = Array(repeating: nil, count: DrawListRing.bufferCount)
        runs = try GlyphRunStore(device: device, byteBudget: runByteBudget)
        records.reserveCapacity(Limits.maxNodesPerCanvas)
        quads.reserveCapacity(Limits.maxTextLength)
    }

    /// Returns the record buffer of the current frame with room for the records of the frame
    /// and the pass, made or grown if needed, or `nil` if Metal makes no buffer.
    func recordBuffer() -> (any MTLBuffer)? {
        let needed = recordsUsed + records.count
        precondition(needed <= Self.recordCapacity, "The records fit the buffer of the frame")
        let stride = MemoryLayout<GlyphRecord>.stride
        if let buffer = recordBuffers[recordIndex], buffer.length >= needed * stride {
            return buffer
        }
        let count = min(
            max(
                needed,
                2 * (recordBuffers[recordIndex]?.length ?? 0) / stride,
                Self.initialRecords
            ),
            Self.recordCapacity
        )
        // The records of the earlier passes of the frame stay in the old buffer, which their
        // command buffer holds. The new one keeps their offsets.
        let buffer = device.makeBuffer(length: count * stride, options: .storageModeShared)
        buffer?.label = "Glyph records"
        recordBuffers[recordIndex] = buffer
        return buffer
    }

    /// The quads that the current pass can still add.
    var remainingQuads: Int { capacity - used - passQuads }

    /// `true` if the current pass can add one more record.
    var hasRoomForRecord: Bool {
        recordsUsed + records.count < Self.recordCapacity
    }

    /// Starts a frame with the next record buffer and the build time of the frame.
    func beginFrame(now: TimeInterval) {
        frameBuildDeadline = now + Self.buildBudget
        recordIndex = (recordIndex + 1) % recordBuffers.count
        used = 0
        recordsUsed = 0
        records.removeAll(keepingCapacity: true)
        passQuads = 0
    }

    /// Starts a pass that builds new runs until `deadline` or the end of the build time of the
    /// frame.
    func beginPass(deadline: TimeInterval) {
        records.removeAll(keepingCapacity: true)
        passQuads = 0
        passBuilds = 0
        buildDeadline = min(deadline, frameBuildDeadline)
    }

    /// Returns `true` if the pass can build one more run. The first build of a pass always runs,
    /// so that each pass makes progress.
    func mayBuild(now: () -> TimeInterval) -> Bool {
        guard passBuilds > 0, passBuilds.isMultiple(of: Self.buildCheckInterval) else {
            return true
        }
        return now() <= buildDeadline
    }

    /// Counts a build of the current pass.
    func noteBuild() {
        passBuilds += 1
    }

    /// Adds the record of a run with its box at `base` in target pixels.
    ///
    /// - Precondition: The pass has room for the record and its quads.
    func addRecord(base: SIMD2<Float>, run: GlyphRunStore.Run) {
        precondition(run.count <= remainingQuads && hasRoomForRecord, "The record fits the pass")
        let (buffer, offset) = runs.location(of: run.block)
        records.append(
            GlyphRecord(
                base: base,
                runStart: UInt32(offset),
                count: UInt32(run.count),
                prefix: UInt32(passQuads),
                buffer: UInt32(buffer)
            )
        )
        passQuads += run.count
    }

    /// Ends a pass: its records and quads stay in the buffers of the frame.
    func endPass() {
        assert(used + passQuads <= capacity, "The quads fit the frame")
        used += passQuads
        recordsUsed += records.count
        records.removeAll(keepingCapacity: true)
        passQuads = 0
    }
}
