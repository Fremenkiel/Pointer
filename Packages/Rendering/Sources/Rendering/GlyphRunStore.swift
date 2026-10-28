import Metal
import Model

/// The stored glyph runs of the text: the quads of one box or card title at one atlas exponent,
/// in canvas points from the top-left corner of the box, in shared buffers of 1 MB (architecture.md
/// 5.4.1, D-94, D-188). The draw reads the buffers through a table of their GPU addresses,
/// so the store grows in small steps.
///
/// A `SlabAllocator` hands out the ranges in quads, as for the points of the strokes. A run is
/// valid while its layout version and the generations of its pages stay. Past the byte budget,
/// the runs that no recent frame drew go first. A run that a frame in flight reads is freed only
/// after that frame.
final class GlyphRunStore {
    /// The key of a run: the item and the atlas exponent.
    struct Key: Hashable {
        let item: GreenItem
        let exponent: Int8
    }

    /// One stored run.
    struct Run {
        let block: ArenaBlock
        /// The quads of the run: the glyphs with pixels.
        let count: Int
        /// The layout version of the item at the build.
        let version: UInt32
        /// The atlas pages that the run reads, and their generations at the build.
        let pages: [Int]
        let generations: [UInt32]
        /// The last frame that drew the run.
        var lastFrame: UInt64
    }

    /// The bytes of one stored quad.
    static let bytesPerQuad = MemoryLayout<StoredGlyph>.stride
    /// The bytes of one buffer: 5 slabs, so that the first run of a canvas takes 1 MB.
    static let bytesPerBuffer = 1 << 20
    /// The most buffers: `RunBuffers` in Shaders.metal has this many addresses.
    static let maxBuffers = 32
    /// The frames that can still read a run after it was drawn.
    static let framesInFlight = UInt64(DrawListRing.bufferCount)
    /// The frames after its last draw before a run of the exponent of a new run can go: 1 s at
    /// 120 Hz. A build takes fewer frames, so it never evicts its own runs and builds them again.
    /// Past the budget, the rest of the build takes the CPU path (D-188).
    static let sameExponentAge: UInt64 = 120

    let device: any MTLDevice
    /// The largest size of all buffers together, in bytes.
    let byteBudget: Int
    /// The slabs of one buffer.
    let slabsPerBuffer: Int
    private(set) var buffers: [any MTLBuffer] = []
    /// The GPU address of each buffer, for the draw of the stored glyphs.
    let addresses: any MTLBuffer
    private var allocator = SlabAllocator(slabCount: 0)
    private(set) var runs: [Key: Run] = [:]
    /// The blocks of replaced or evicted runs with the frame after which they are free.
    private var pendingFrees: [(block: ArenaBlock, after: UInt64)] = []
    /// The frame in which an eviction found no run to free. The rest of that frame stores no
    /// new run, so that a full store costs one scan per frame.
    private var exhaustedFrame: UInt64 = 0
    /// The keys of the stale runs of one eviction. The list stays, so that an eviction on the
    /// render thread allocates nothing (PERF-01, review of 2026-10-28).
    private var staleKeys: [Key] = []

    /// Makes an empty store. It makes its first buffer at the first run.
    ///
    /// - Precondition: The budget holds one slab and at most `maxBuffers` buffers.
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make the address table.
    init(device: any MTLDevice, byteBudget: Int) throws(RenderingError) {
        let slabBytes = SlabAllocator.slabPoints * Self.bytesPerQuad
        precondition(byteBudget >= slabBytes, "The run budget holds a slab")
        precondition(
            byteBudget <= Self.maxBuffers * Self.bytesPerBuffer,
            "The run budget fits \(Self.maxBuffers) buffers"
        )
        guard
            let addresses = device.makeBuffer(
                length: Self.maxBuffers * MemoryLayout<UInt64>.stride,
                options: .storageModeShared
            )
        else { throw .resourceUnavailable("glyph run addresses") }
        addresses.label = "Glyph run addresses"
        self.addresses = addresses
        self.device = device
        self.byteBudget = byteBudget
        slabsPerBuffer = min(Self.bytesPerBuffer, byteBudget) / slabBytes
    }

    /// The bytes of all buffers.
    var footprint: Int { allocator.slabCount * SlabAllocator.slabPoints * Self.bytesPerQuad }

    /// Returns the run of a key if it is valid for the version and the atlas, and marks it as
    /// drawn by the frame.
    func validRun(_ key: Key, version: UInt32, atlas: GlyphAtlas, frame: UInt64) -> Run? {
        // One hash per lookup: the index serves the read and the write of the frame.
        guard let index = runs.index(forKey: key) else { return nil }
        let run = runs.values[index]
        guard run.version == version, Self.pagesMatch(run, atlas.generations) else {
            release(key, frame: frame)
            return nil
        }
        runs.values[index].lastFrame = frame
        return run
    }

    private static func pagesMatch(_ run: Run, _ generations: [UInt32]) -> Bool {
        assert(run.pages.count == run.generations.count, "Each page has its generation")
        for (index, page) in run.pages.enumerated() {
            guard generations.indices.contains(page), generations[page] == run.generations[index]
            else { return false }
        }
        return true
    }

    /// Stores the quads of a new run, or returns `nil` if the budget holds no room, also after
    /// the runs that no recent frame drew are gone.
    ///
    /// - Precondition: `quads` holds 1 to `SlabAllocator.slabPoints` quads.
    func store(
        _ quads: [StoredGlyph],
        key: Key,
        version: UInt32,
        pages: (indices: [Int], generations: [UInt32]),
        frame: UInt64
    ) -> Run? {
        precondition(
            !quads.isEmpty && quads.count <= SlabAllocator.slabPoints,
            "A run holds 1 to \(SlabAllocator.slabPoints) quads"
        )
        release(key, frame: frame)
        freePending(before: frame)
        guard let block = allocate(quads.count, exponent: key.exponent, frame: frame) else {
            return nil
        }
        write(quads, to: block)
        let run = Run(
            block: block,
            count: quads.count,
            version: version,
            pages: pages.indices,
            generations: pages.generations,
            lastFrame: frame
        )
        runs[key] = run
        return run
    }

    /// Returns the buffer of a run and the index of its first quad in that buffer.
    func location(of block: ArenaBlock) -> (buffer: Int, offset: Int) {
        let quadsPerBuffer = slabsPerBuffer * SlabAllocator.slabPoints
        let buffer = block.start / quadsPerBuffer
        precondition(buffers.indices.contains(buffer), "Block \(block) is outside the store")
        return (buffer, block.start - buffer * quadsPerBuffer)
    }

    /// Takes a run out of the list. Its block is free after the frames in flight.
    private func release(_ key: Key, frame: UInt64) {
        guard let run = runs.removeValue(forKey: key) else { return }
        pendingFrees.append((run.block, max(frame, run.lastFrame) + Self.framesInFlight))
    }

    private func freePending(before frame: UInt64) {
        precondition(frame > 0, "Frames count from 1")
        guard !pendingFrees.isEmpty else { return }
        var kept = 0
        for index in pendingFrees.indices {
            let pending = pendingFrees[index]
            if pending.after < frame {
                allocator.free(pending.block)
            } else {
                pendingFrees[kept] = pending
                kept += 1
            }
        }
        pendingFrees.removeLast(pendingFrees.count - kept)
    }

    /// Allocates a block: from the free slabs, from a new buffer, or after an eviction.
    private func allocate(_ quads: Int, exponent: Int8, frame: UInt64) -> ArenaBlock? {
        if let block = allocator.allocate(points: quads) { return block }
        if addBuffer(), let block = allocator.allocate(points: quads) { return block }
        guard exhaustedFrame != frame else { return nil }
        guard evict(atLeast: quads, exponent: exponent, frame: frame),
            let block = allocator.allocate(points: quads)
        else {
            exhaustedFrame = frame
            return nil
        }
        return block
    }

    /// Frees each stale run in one scan: the runs of other exponents after the frames in flight,
    /// and the runs of `exponent` after `sameExponentAge` frames. A sort of the runs by age took
    /// 3.5 ms for the 9,000 runs of D-56 on the iPad, and a stale run is not needed anyway.
    ///
    /// - Returns: `false` if no run can go.
    private func evict(atLeast quads: Int, exponent: Int8, frame: UInt64) -> Bool {
        precondition(quads > 0, "An eviction frees room for a run")
        // `Dictionary.filter` makes a new dictionary of all kept runs, up to 9,000 for the D-56
        // text, so the scan collects the stale keys and removes them in place.
        staleKeys.removeAll(keepingCapacity: true)
        for (key, run) in runs {
            let age = key.exponent == exponent ? Self.sameExponentAge : Self.framesInFlight
            if run.lastFrame + age < frame { staleKeys.append(key) }
        }
        for key in staleKeys {
            guard let run = runs.removeValue(forKey: key) else {
                preconditionFailure("A stale run left the store during its eviction")
            }
            allocator.free(run.block)
        }
        return !staleKeys.isEmpty
    }

    /// Adds one buffer within the budget.
    private func addBuffer() -> Bool {
        let slabBytes = SlabAllocator.slabPoints * Self.bytesPerQuad
        let slabs = min(slabsPerBuffer, byteBudget / slabBytes - allocator.slabCount)
        guard slabs > 0, buffers.count < Self.maxBuffers else { return false }
        guard
            let buffer = device.makeBuffer(
                length: slabs * slabBytes,
                options: .storageModeShared
            )
        else { return false }
        buffer.label = "Glyph runs \(buffers.count)"
        setAddress(of: buffer, at: buffers.count)
        buffers.append(buffer)
        allocator.addSlabs(slabs)
        assert(footprint <= byteBudget, "The run store passed its budget")
        return true
    }
}
