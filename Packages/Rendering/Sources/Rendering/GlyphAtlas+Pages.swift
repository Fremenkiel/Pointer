import Metal

/// The page textures of the atlas: from the heap of the page table or from the device, and the
/// page that can go when a new page needs room (D-189).
extension GlyphAtlas {
    /// Makes a page texture: from the heap of the page table, or from the device. A full heap
    /// drops the oldest pages until the texture fits, because pages of different sides can
    /// leave gaps.
    func makeTexture(
        _ descriptor: MTLTextureDescriptor,
        frame: UInt64
    ) -> (any MTLTexture)? {
        guard let pageTable else { return device.makeTexture(descriptor: descriptor) }
        for _ in 0...pages.count {
            if let texture = pageTable.makeTexture(descriptor) { return texture }
            guard let oldest = oldestDroppable(before: frame) else { return nil }
            drop(oldest)
        }
        return nil
    }

    /// The page that frames used least recently and that no frame in flight reads, or `nil`.
    func oldestDroppable(before frame: UInt64) -> Int? {
        var oldest: Int?
        var oldestFrame = UInt64.max
        for (index, page) in pages.enumerated() {
            guard let page, page.lastFrame + dropMargin < frame else { continue }
            if page.lastFrame < oldestFrame {
                oldest = index
                oldestFrame = page.lastFrame
            }
        }
        return oldest
    }

    /// Moves the pages into the heaps of a new page table, for the stored runs: it drops each
    /// page of the device, and the glyphs that a frame needs again go into the heaps (D-189). A
    /// frame in flight keeps the old textures, because its command buffer holds them.
    ///
    /// - Returns: `false` if Metal makes no page table. The atlas then stays as it is.
    func makeBindless() -> Bool {
        guard pageTable == nil else { return true }
        guard let table = GlyphPageTable(device: device, byteBudget: byteBudget) else {
            return false
        }
        for index in pages.indices where pages[index] != nil {
            drop(index)
        }
        assert(byteCount == 0, "No page of the device stays")
        setPageTable(table)
        return true
    }
}
