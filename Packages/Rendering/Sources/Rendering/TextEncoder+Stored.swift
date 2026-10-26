import Geometry
import Metal
import QuartzCore

/// The stored glyph runs of a text pass: a record per box, the expansion into glyph quads, and
/// one draw over the atlas pages of the heap (architecture.md 5.4.1, D-94, D-189, D-190).
extension TextEncoder {
    /// The outcome of the stored path for one layout.
    enum StoredOutcome {
        /// The record of the run is in the pass, or the layout draws nothing.
        case added
        /// The encoder has no stored runs, or the store or the atlas has no room. The CPU path
        /// draws the layout.
        case noRoom
        /// The pass spent its build time. The item stays for the next pass.
        case later
    }

    /// The result of the build of a run.
    private enum Build {
        /// The stored run.
        case run(GlyphRunStore.Run)
        /// The layout has no glyph with pixels, so it draws nothing.
        case empty
        /// The atlas or the run store holds no room. The CPU path draws the layout.
        case full
    }

    /// Adds the stored run of a layout to the pass: a valid run, or a run that it builds now.
    func appendStored(
        _ layout: TextLayout,
        key: GlyphRunStore.Key,
        version: UInt32,
        at origin: Point,
        _ place: Place
    ) -> StoredOutcome {
        let frame = place.frame
        precondition(Int(key.exponent) == place.exponent, "The key has the exponent of the pass")
        guard let stored = storedRoom(for: layout) else { return .noRoom }
        let exponent = Int(key.exponent)
        let run: GlyphRunStore.Run
        if let valid = stored.runs.validRun(key, version: version, atlas: atlas, frame: frame) {
            run = valid
        } else {
            // Past the build time of the pass, the item stays for the next frame.
            guard stored.mayBuild(now: CACurrentMediaTime) else { return .later }
            stored.noteBuild()
            switch buildRun(layout, key: key, version: version, stored: stored, frame: frame) {
            case .run(let built): run = built
            case .empty: return .added
            case .full: return .noRoom
            }
        }
        for page in run.pages {
            atlas.markUsed(page: page, frame: frame)
        }
        let mapping = Self.mapping(of: origin, target: place.target, exponent: exponent)
        stored.addRecord(base: mapping.base, run: run)
        return .added
    }

    /// Places the glyphs of a layout in the atlas and stores their quads as a run.
    private func buildRun(
        _ layout: TextLayout,
        key: GlyphRunStore.Key,
        version: UInt32,
        stored: StoredText,
        frame: UInt64
    ) -> Build {
        precondition(layout.fontIndices.count == layout.glyphs.count, "Each glyph has a font")
        // Local lists, as in `writeQuads`: each access to a stored property costs a check. The
        // properties let go of their storage, so that the lists grow in place and do not copy.
        var quads = stored.quads
        var pages = (indices: stored.pages, generations: stored.generations)
        stored.quads = []
        stored.pages = []
        stored.generations = []
        quads.removeAll(keepingCapacity: true)
        pages.indices.removeAll(keepingCapacity: true)
        pages.generations.removeAll(keepingCapacity: true)
        defer {
            stored.quads = quads
            stored.pages = pages.indices
            stored.generations = pages.generations
        }
        let isComplete = placeGlyphs(
            of: layout,
            exponent: Int(key.exponent),
            frame: frame,
            into: &quads,
            pages: &pages
        )
        guard isComplete else { return .full }
        guard !quads.isEmpty else { return .empty }
        guard
            let run = stored.runs.store(
                quads,
                key: key,
                version: version,
                pages: pages,
                frame: frame
            )
        else { return .full }
        return .run(run)
    }

    /// Writes the stored quads of the glyphs with pixels and the pages that they read.
    ///
    /// - Returns: `false` if the atlas holds no room for a glyph.
    private func placeGlyphs(
        of layout: TextLayout,
        exponent: Int,
        frame: UInt64,
        into quads: inout [StoredGlyph],
        pages: inout (indices: [Int], generations: [UInt32])
    ) -> Bool {
        let fonts = layout.fonts
        let indices = layout.fontIndices
        var fontIndex = UInt8(0)
        var fontID = atlas.fontID(of: fonts[0])
        for (index, glyph) in layout.glyphs.enumerated() {
            if indices[index] != fontIndex {
                fontIndex = indices[index]
                fontID = atlas.fontID(of: fonts[Int(fontIndex)])
            }
            guard
                let place = atlas.placement(
                    of: glyph.glyph,
                    font: fonts[Int(fontIndex)],
                    fontID: fontID,
                    exponent: exponent,
                    frame: frame
                )
            else { return false }
            guard place.page >= 0 else { continue }
            if !pages.indices.contains(place.page) {
                pages.indices.append(place.page)
                pages.generations.append(atlas.generations[place.page])
                atlas.markUsed(page: place.page, frame: frame)
            }
            // A placement without an index has no place in the table: the CPU path draws it.
            guard place.id >= 0 else { return false }
            quads.append(StoredGlyph(x: glyph.x, line: glyph.line, place: UInt32(place.id)))
        }
        assert(pages.indices.count == pages.generations.count, "Each page has its generation")
        return true
    }

    /// Makes the stored runs at the start of a pass, after the first large layout. A canvas of
    /// cards and short text never makes them, so it keeps the atlas and the frames of the CPU
    /// path: the stored setup alone made the main thread of a card pan 16 % slower at its p99
    /// (40 pairs, p 0.0022).
    func startStored() {
        wantsStored = false
        guard stored == nil, let limits = storedLimits, atlas.makeBindless() else { return }
        do {
            let made = try StoredText(
                device: resources.device,
                capacity: limits.capacity,
                runByteBudget: limits.runBudget
            )
            made.beginFrame(now: CACurrentMediaTime())
            stored = made
        } catch {
            assertionFailure("The stored runs failed: \(error)")
        }
    }

    /// Returns the stored runs if a layout takes a run and the pass has room for it. The first
    /// large layout of a canvas without stored runs asks the next pass to start them.
    private func storedRoom(for layout: TextLayout) -> StoredText? {
        let glyphs = layout.glyphs.count
        guard glyphs >= StoredText.minimumGlyphs else { return nil }
        guard let stored else {
            if storedLimits != nil { wantsStored = true }
            return nil
        }
        guard stored.hasRoomForRecord, glyphs <= stored.remainingQuads else { return nil }
        return stored
    }
}
