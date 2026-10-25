import CoreText
import Metal
import UIKit
import os

/// The glyph atlas of the text (architecture.md 5.4, D-29, D-81).
///
/// Core Text draws each glyph once per scale into a page texture. The scale is the pixels per
/// canvas point, rounded up to the next power of two. The atlas has a byte budget. Past the
/// budget, the page that a frame used least recently goes first. A page that the current frame
/// uses never goes.
final class GlyphAtlas {
    /// The place of one glyph bitmap in a page.
    struct Placement: Equatable {
        /// The index of the page in `pages`, or -1 for a glyph without pixels, as a space.
        let page: Int
        /// The top-left corner of the bitmap in the page, in pixels.
        let origin: SIMD2<Float>
        /// The size of the bitmap, in pixels.
        let size: SIMD2<Float>
        /// The top-left corner of the bitmap from the baseline point of the glyph, in pixels.
        let bearing: SIMD2<Float>
    }

    /// The key of a glyph bitmap. The font is a number of `fontID(of:)`, because a string key
    /// cost too much in a frame with many glyphs (task 2.4 of docs/m5-plan.md).
    struct Key: Hashable {
        let font: Int32
        let glyph: CGGlyph
        let exponent: Int8
    }

    /// One page: a texture of one scale with shelves of bitmaps.
    struct Page {
        let texture: any MTLTexture
        let exponent: Int
        var shelfX = 0
        var shelfY = 0
        var shelfHeight = 0
        var lastFrame: UInt64 = 0
        var keys: [Key] = []
    }

    /// The smallest and the largest scale exponent: 0.25 to 32 pixels per canvas point. Zoom
    /// 0.25 to 8 at the display scales 1 to 3 stays inside (CAN-04).
    static let exponentRange = -2...5
    /// The pixels of empty space around each bitmap, so that the linear filter reads no
    /// neighbor.
    static let padding = 1
    /// The smallest and the largest side of a page, in pixels.
    static let pageSides = 256...2048
    /// The rows of the largest glyph that a page holds at least.
    static let rowsPerPage = 12

    private let device: any MTLDevice
    /// The byte budget of all pages.
    let byteBudget: Int
    private(set) var pages: [Page?] = []
    private var placements: [Key: Placement] = [:]
    /// The numbers of the fonts by name. SF Mono has the number 0.
    private var fontIDs: [String: Int32] = [:]
    /// The places of the SF Mono glyphs below `tableGlyphs`, one row of the flat table per
    /// scale, for a lookup without a hash and without a reference count of a nested array.
    private var table: [Placement?]
    /// The SF Mono glyphs that the tables hold.
    static let tableGlyphs = 4_096
    /// The bytes of all pages.
    private(set) var byteCount = 0
    private static let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Rendering")

    /// Makes an empty atlas.
    ///
    /// - Precondition: `byteBudget` is positive.
    init(device: any MTLDevice, byteBudget: Int) {
        precondition(byteBudget > 0, "The atlas budget is positive, got \(byteBudget)")
        self.device = device
        self.byteBudget = byteBudget
        table = Array(repeating: nil, count: Self.exponentRange.count * Self.tableGlyphs)
        fontIDs[TextLayout.baseFont.fontName] = 0
    }

    /// Returns the number of a font, and gives a new font the next number.
    func fontID(of font: UIFont) -> Int32 {
        precondition(!font.fontName.isEmpty, "A font has a name")
        if let known = fontIDs[font.fontName] { return known }
        let next = Int32(fontIDs.count)
        fontIDs[font.fontName] = next
        return next
    }

    /// Marks a page as used by a frame, so that a new glyph of that frame does not drop it.
    func markUsed(page: Int, frame: UInt64) {
        precondition(frame > 0, "Frames count from 1")
        guard page >= 0, pages.indices.contains(page) else { return }
        pages[page]?.lastFrame = frame
    }

    /// Returns the scale exponent for a number of pixels per canvas point: the next power of two
    /// at or above it, inside `exponentRange`.
    ///
    /// - Precondition: `pixelsPerCanvasPoint` is positive and finite.
    static func exponent(pixelsPerCanvasPoint: Double) -> Int {
        precondition(
            pixelsPerCanvasPoint > 0 && pixelsPerCanvasPoint.isFinite,
            "Pixels per canvas point must be positive, got \(pixelsPerCanvasPoint)"
        )
        let exponent = Int(log2(pixelsPerCanvasPoint).rounded(.up))
        return min(max(exponent, exponentRange.lowerBound), exponentRange.upperBound)
    }

    // Only the tests read it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// Returns the place of a glyph at a scale, and draws it into a page if it is new. The frame
    /// marks the page as used.
    ///
    /// - Precondition: `exponent` is inside `exponentRange`.
    /// - Returns: The place, or `nil` if the budget holds no new page. The glyph then does not
    ///   show in this frame, and the log has the fault.
    func placement(
        // swiftlint:enable unused_declaration
        of glyph: CGGlyph,
        font: UIFont,
        exponent: Int,
        frame: UInt64
    ) -> Placement? {
        precondition(Self.exponentRange.contains(exponent), "Exponent \(exponent) is outside")
        assert(!fontIDs.isEmpty, "SF Mono has its number")
        return placement(
            of: glyph,
            font: font,
            fontID: fontID(of: font),
            exponent: exponent,
            frame: frame
        )
    }

    /// Returns the place of a glyph of a font with a known number, as `placement(of:font:...)`
    /// does. The caller marks the page of the result as used with `markUsed(page:frame:)`.
    ///
    /// - Precondition: `exponent` is inside `exponentRange`.
    func placement(
        of glyph: CGGlyph,
        font: UIFont,
        fontID: Int32,
        exponent: Int,
        frame: UInt64
    ) -> Placement? {
        precondition(Self.exponentRange.contains(exponent), "Exponent \(exponent) is outside")
        precondition(fontID >= 0, "Font number \(fontID) is not negative")
        let row = exponent - Self.exponentRange.lowerBound
        let isTabled = fontID == 0 && Int(glyph) < Self.tableGlyphs
        if isTabled, let placement = table[row * Self.tableGlyphs + Int(glyph)] {
            return placement
        }
        let key = Key(font: fontID, glyph: glyph, exponent: Int8(exponent))
        if let placement = placements[key] {
            return placement
        }
        let raster = GlyphRaster(glyph: glyph, font: font, scale: Self.scale(of: exponent))
        guard raster.width > 0, raster.height > 0 else {
            let empty = Placement(page: -1, origin: .zero, size: .zero, bearing: .zero)
            placements[key] = empty
            if isTabled { setTable(row, Int(glyph), empty) }
            return empty
        }
        guard let index = page(for: raster, exponent: exponent, frame: frame) else {
            Self.logger.error("The glyph atlas has no room within \(self.byteBudget) bytes")
            return nil
        }
        let placement = insert(raster, key: key, page: index)
        if isTabled { setTable(row, Int(glyph), placement) }
        assert(placement.page == index, "The glyph lands in the found page")
        return placement
    }

    /// Writes one entry of the table of a scale.
    private func setTable(_ row: Int, _ glyph: Int, _ placement: Placement) {
        precondition(glyph >= 0 && glyph < Self.tableGlyphs, "Glyph \(glyph) is outside the table")
        table[row * Self.tableGlyphs + glyph] = placement
    }

    /// The pixels per canvas point of a scale exponent.
    static func scale(of exponent: Int) -> Double {
        pow(2, Double(exponent))
    }

    /// Returns a page of the exponent with room for the raster, or makes one.
    private func page(for raster: GlyphRaster, exponent: Int, frame: UInt64) -> Int? {
        precondition(raster.width > 0 && raster.height > 0, "Only a bitmap needs a page")
        let width = raster.width + 2 * Self.padding
        let height = raster.height + 2 * Self.padding
        for (index, page) in pages.enumerated() {
            guard let page, page.exponent == exponent else { continue }
            if fits(width: width, height: height, in: page) { return index }
        }
        let side = Self.pageSide(exponent: exponent)
        guard width <= side, height <= side else { return nil }
        let bytes = side * side
        guard makeRoom(for: bytes, frame: frame) else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: side,
            height: side,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Glyph atlas"
        let page = Page(texture: texture, exponent: exponent, lastFrame: frame)
        byteCount += bytes
        if let free = pages.firstIndex(where: { $0 == nil }) {
            pages[free] = page
            return free
        }
        pages.append(page)
        assert(byteCount <= byteBudget, "The atlas passed its budget")
        return pages.count - 1
    }

    /// The side of a page: room for `rowsPerPage` rows of a line of text at the scale.
    static func pageSide(exponent: Int) -> Int {
        let row = Double(TextLayout.lineHeight) * scale(of: exponent) * 1.5
        let wanted = Int((row * Double(rowsPerPage)).rounded(.up))
        var side = pageSides.lowerBound
        for _ in 0..<8 where side < wanted && side < pageSides.upperBound {
            side *= 2
        }
        return side
    }

    private func fits(width: Int, height: Int, in page: Page) -> Bool {
        let side = page.texture.width
        if page.shelfX + width <= side, page.shelfY + max(page.shelfHeight, height) <= side {
            return true
        }
        return page.shelfY + page.shelfHeight + height <= side && width <= side
    }

    /// Drops the pages that frames used least recently until `bytes` more fit the budget. A page
    /// of the current frame stays.
    private func makeRoom(for bytes: Int, frame: UInt64) -> Bool {
        precondition(bytes > 0, "A page takes bytes, got \(bytes)")
        for _ in 0..<pages.count where byteCount + bytes > byteBudget {
            let candidates = pages.indices.filter { index in
                guard let page = pages[index] else { return false }
                return page.lastFrame < frame
            }
            guard
                let oldest = candidates.min(by: { lhs, rhs in
                    (pages[lhs]?.lastFrame ?? 0) < (pages[rhs]?.lastFrame ?? 0)
                })
            else { return false }
            drop(oldest)
        }
        return byteCount + bytes <= byteBudget
    }

    private func drop(_ index: Int) {
        precondition(pages.indices.contains(index), "Page \(index) is outside the list")
        guard let page = pages[index] else { return }
        for key in page.keys {
            placements.removeValue(forKey: key)
            let row = Int(key.exponent) - Self.exponentRange.lowerBound
            if key.font == 0, Int(key.glyph) < Self.tableGlyphs {
                table[row * Self.tableGlyphs + Int(key.glyph)] = nil
            }
        }
        byteCount -= page.texture.width * page.texture.height
        pages[index] = nil
        assert(byteCount >= 0, "The atlas counts no negative bytes")
    }

    /// Puts the raster on the shelf of a page and uploads its pixels.
    private func insert(_ raster: GlyphRaster, key: Key, page index: Int) -> Placement {
        precondition(raster.width > 0 && raster.height > 0, "Only a bitmap goes into a page")
        guard var page = pages[index] else { preconditionFailure("Page \(index) is gone") }
        let width = raster.width + 2 * Self.padding
        let height = raster.height + 2 * Self.padding
        if page.shelfX + width > page.texture.width {
            page.shelfY += page.shelfHeight
            page.shelfX = 0
            page.shelfHeight = 0
        }
        let x = page.shelfX + Self.padding
        let y = page.shelfY + Self.padding
        raster.upload(into: page.texture, x: x, y: y)
        page.shelfX += width
        page.shelfHeight = max(page.shelfHeight, height)
        page.keys.append(key)
        assert(page.shelfY + page.shelfHeight <= page.texture.height, "The shelf fits the page")
        pages[index] = page
        let placement = Placement(
            page: index,
            origin: SIMD2(Float(x), Float(y)),
            size: SIMD2(Float(raster.width), Float(raster.height)),
            bearing: raster.bearing
        )
        placements[key] = placement
        return placement
    }
}
