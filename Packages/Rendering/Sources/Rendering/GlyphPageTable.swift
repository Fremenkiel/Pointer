import Metal

/// The pages of a glyph atlas in heaps, with a buffer of their texture handles, so that one draw
/// reads each page (architecture.md 5.4.1, D-189). The stored runs of the text use it.
///
/// The heaps come in chunks of one page of the largest side, made when a page needs room, so
/// that a canvas with little text holds little memory. A chunk without a page goes.
final class GlyphPageTable {
    /// The pages that the table holds: `GlyphPages` in Shaders.metal has this many handles. A
    /// budget of 16 MB holds at most 256 pages of the smallest side.
    static let capacity = 256

    private let device: any MTLDevice
    /// The bytes of one heap: one page of the largest side with its alignment.
    let chunkBytes: Int
    /// The most heaps: the budget in chunks and one more, because pages of different sides
    /// leave gaps.
    let maxHeaps: Int
    /// The heaps of the page textures. A pass makes them resident with `useHeaps`.
    private(set) var heaps: [any MTLHeap] = []
    /// The texture handle of each page index, `MTLResourceID` values.
    let buffer: any MTLBuffer
    /// The places of the glyph bitmaps by their index, `GlyphPlace` values, for the stored runs,
    /// or `nil` before the first one. It grows by doubling.
    private(set) var places: (any MTLBuffer)?
    /// The placement indices that a page drop freed.
    private var freePlaces: [Int32] = []
    /// The next placement index that was never used.
    private var nextPlace: Int32 = 0
    /// The first capacity of the places, in placements.
    static let initialPlaces = 4_096
    /// A test hook that makes the buffer of the places in place of the device, or `nil`.
    private let makePlaces: ((Int) -> (any MTLBuffer)?)?

    /// Makes an empty table.
    ///
    /// - Precondition: The budget holds at most `capacity` pages of the smallest side.
    /// - Returns: `nil` if Metal makes no buffer. The atlas then uses textures of the device,
    ///   and the text takes the CPU path.
    convenience init?(device: any MTLDevice, byteBudget: Int) {
        self.init(device: device, byteBudget: byteBudget, makePlaces: nil)
    }

    /// Makes an empty table with a test hook for the buffer of the places.
    init?(device: any MTLDevice, byteBudget: Int, makePlaces: ((Int) -> (any MTLBuffer)?)?) {
        let smallest = GlyphAtlas.pageSides.lowerBound * GlyphAtlas.pageSides.lowerBound
        precondition(byteBudget / smallest <= Self.capacity, "The table holds each page")
        guard
            let buffer = device.makeBuffer(
                length: Self.capacity * MemoryLayout<MTLResourceID>.stride,
                options: .storageModeShared
            )
        else { return nil }
        buffer.label = "Glyph page table"
        let side = GlyphAtlas.pageSides.upperBound
        let descriptor = GlyphAtlas.pageDescriptor(side: side)
        let size = device.heapTextureSizeAndAlign(descriptor: descriptor)
        self.device = device
        self.buffer = buffer
        self.makePlaces = makePlaces
        chunkBytes = (size.size + size.align - 1) / size.align * size.align
        maxHeaps = (byteBudget + chunkBytes - 1) / chunkBytes + 1
    }

    /// Returns a page texture from a heap, from a new heap if none has room, or `nil` if all
    /// heaps are full.
    func makeTexture(_ descriptor: MTLTextureDescriptor) -> (any MTLTexture)? {
        precondition(descriptor.storageMode == .shared, "A page is shared with the CPU")
        for heap in heaps {
            if let texture = heap.makeTexture(descriptor: descriptor) { return texture }
        }
        guard heaps.count < maxHeaps else { return nil }
        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.type = .automatic
        heapDescriptor.storageMode = .shared
        heapDescriptor.size = chunkBytes
        guard let heap = device.makeHeap(descriptor: heapDescriptor) else { return nil }
        heap.label = "Glyph pages \(heaps.count)"
        heaps.append(heap)
        return heap.makeTexture(descriptor: descriptor)
    }

    /// Lets go of the heaps that hold no page after a drop.
    func releaseEmptyHeaps() {
        heaps.removeAll { $0.usedSize == 0 }
        assert(heaps.count <= maxHeaps, "The table holds at most its heaps")
    }

    /// Gives a placement an index in the table of places and writes it there.
    ///
    /// - Returns: The index, or -1 if Metal makes no buffer. The runs then take the CPU path.
    func register(_ placement: GlyphAtlas.Placement) -> Int32 {
        precondition(placement.page >= 0, "Only a glyph with pixels has a place")
        // The index is taken after the buffer exists, so a failed buffer loses no index
        // (review of 2026-10-28, 3.2.12).
        let id = freePlaces.last ?? nextPlace
        guard let places = placesBuffer(holding: Int(id) + 1) else { return -1 }
        if freePlaces.popLast() == nil { nextPlace += 1 }
        writePlace(placement, at: Int(id), in: places)
        return id
    }

    /// Frees the index of a placement of a dropped page. The page stays for the frames in
    /// flight, so no frame reads the index after its reuse.
    func releasePlacement(_ id: Int32) {
        precondition(id >= 0 && id < nextPlace, "Place \(id) was given out")
        freePlaces.append(id)
    }

    /// Returns the buffer of places with room for `count` places, made or doubled if needed. A
    /// frame in flight keeps the old buffer, because its command buffer holds it.
    private func placesBuffer(holding count: Int) -> (any MTLBuffer)? {
        let stride = MemoryLayout<GlyphPlace>.stride
        if let places, places.length >= count * stride { return places }
        let capacity = max(Self.initialPlaces, 2 * (places?.length ?? 0) / stride, count)
        let length = capacity * stride
        let made: (any MTLBuffer)?
        if let makePlaces {
            made = makePlaces(length)
        } else {
            made = device.makeBuffer(length: length, options: .storageModeShared)
        }
        guard let grown = made else { return nil }
        grown.label = "Glyph places"
        if let places { copyPlaces(from: places, to: grown) }
        places = grown
        return grown
    }
}
