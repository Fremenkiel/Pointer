import CoreText
import Geometry
import Model
import UIKit

/// The layout of the text of one text box (architecture.md section 5.4, D-84).
///
/// Core Text lays out the text with the attributes of the edit view: SF Mono at
/// `TextStyle.fontSize`, the fixed line height of the font, and word wrap at
/// `TextStyle.maxWidth`. The positions are in canvas points from the top-left corner of the box.
/// Fallback fonts give the glyphs that SF Mono lacks, so each glyph names its font.
public struct TextLayout: Sendable {
    /// One glyph of the layout, in 8 bytes: a canvas of D-56 holds a million glyphs.
    public struct Glyph: Sendable, Equatable {
        /// The baseline x of the glyph, in canvas points from the left side of the box.
        public let x: Float
        /// The glyph ID in its font.
        public let glyph: CGGlyph
        /// The line of the glyph, from 0.
        public let line: UInt16

        /// The baseline point of the glyph, in canvas points from the top-left corner of the box.
        public var position: SIMD2<Float> {
            SIMD2(x, Float(Double(line) * TextLayout.lineHeight + TextLayout.ascent))
        }
    }

    /// The fonts of the glyphs at `TextStyle.fontSize`: SF Mono first, then fallback fonts.
    public let fonts: [UIFont]
    /// The glyphs, line by line.
    public let glyphs: [Glyph]
    /// The index in `fonts` of the font of each glyph.
    public let fontIndices: [UInt8]
    /// The number of lines. An empty text and a text that ends with a new line count the empty
    /// last line, as the edit view does.
    public let lineCount: Int
    /// The size of the box in canvas points: the widest line without its trailing white space,
    /// and the line count times the line height.
    public let size: Size

    /// The font of the text at a size in points: SF Mono, regular (D-15).
    ///
    /// - Precondition: `size` is positive.
    public static func font(size: Double) -> UIFont {
        precondition(size > 0, "A font size is positive, got \(size)")
        return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// The font of the layout, at `TextStyle.fontSize`.
    static let baseFont = font(size: TextStyle.fontSize)
    /// The height of one line in canvas points: the line height of SF Mono. The edit view uses it
    /// as its fixed line height.
    public static let lineHeight = Double(baseFont.lineHeight)
    /// The distance from the top of a line to its baseline, in canvas points.
    public static let ascent = Double(baseFont.ascender)

    /// Lays out a text.
    ///
    /// - Precondition: The text has at most `Limits.maxTextLength` code points. An empty text is
    ///   allowed, for a box in edit mode.
    public init(text: String) {
        precondition(
            text.unicodeScalars.count <= Limits.maxTextLength,
            "A text box holds at most \(Limits.maxTextLength) code points"
        )
        RenderSignpost.begin("TextLayout")
        defer { RenderSignpost.end("TextLayout") }
        let length = text.utf16.count
        // Each glyph comes from at least one UTF-16 unit in almost all text, so one reserve
        // holds the glyphs: a reserve per run copied the list at each line (review of M5).
        var builder = Builder(capacity: length)
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: Self.baseFont]
        )
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var start = 0
        // Each line takes at least one UTF-16 unit, so the text bounds the loop (FLOW-03).
        for _ in 0..<length where start < length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, TextStyle.maxWidth)
            assert(count > 0, "A line takes at least one unit")
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            builder.append(line)
            start += max(count, 1)
        }
        if length == 0 || text.hasSuffix("\n") || text.hasSuffix("\r") {
            builder.appendEmptyLine()
        }
        fonts = builder.fonts
        glyphs = builder.glyphs
        fontIndices = builder.fontIndices
        lineCount = builder.lineCount
        size = Size(width: builder.width, height: Double(builder.lineCount) * Self.lineHeight)
        assert(lineCount >= 1, "A layout has one line at least")
    }

    /// Collects the lines of a layout.
    private struct Builder {
        var fonts: [UIFont] = [TextLayout.baseFont]
        var glyphs: [Glyph] = []
        var fontIndices: [UInt8] = []
        var lineCount = 0
        var width = 0.0
        /// The glyph IDs and positions of one run, reused by each run.
        private var runIDs: [CGGlyph] = []
        private var runPoints: [CGPoint] = []

        init(capacity: Int) {
            precondition(capacity >= 0, "A capacity is not negative, got \(capacity)")
            glyphs.reserveCapacity(capacity)
            fontIndices.reserveCapacity(capacity)
        }

        mutating func append(_ line: CTLine) {
            precondition(lineCount < Int(UInt16.max), "Line \(lineCount) fits the glyph line")
            let total = CTLineGetTypographicBounds(line, nil, nil, nil)
            let trailing = CTLineGetTrailingWhitespaceWidth(line)
            assert(total.isFinite && trailing.isFinite, "Line \(lineCount) has a finite width")
            width = max(width, total - trailing)
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
            for run in runs {
                append(run, line: UInt16(lineCount))
            }
            lineCount += 1
            assert(width >= 0, "A line width is not negative")
        }

        mutating func appendEmptyLine() {
            lineCount += 1
        }

        private mutating func append(_ run: CTRun, line: UInt16) {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { return }
            runIDs.removeAll(keepingCapacity: true)
            runPoints.removeAll(keepingCapacity: true)
            runIDs.append(contentsOf: repeatElement(0, count: count))
            runPoints.append(contentsOf: repeatElement(.zero, count: count))
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &runIDs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &runPoints)
            assert(runIDs.count == runPoints.count, "Each glyph of a run has a position")
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let font = attributes[NSAttributedString.Key.font] as? UIFont ?? TextLayout.baseFont
            let index = fontIndex(font)
            precondition(index < fonts.count, "Font \(index) is in the font table")
            // The glyphs of a run share the baseline of the line, so only x is kept.
            for (glyph, point) in zip(runIDs, runPoints) {
                glyphs.append(Glyph(x: Float(point.x), glyph: glyph, line: line))
            }
            fontIndices.append(contentsOf: repeatElement(UInt8(index), count: count))
        }

        private mutating func fontIndex(_ font: UIFont) -> Int {
            // Core Text gives the runs of SF Mono the font of the attributes, so an identity
            // check skips the compare of the names.
            if font === fonts[0] { return 0 }
            if let index = fonts.firstIndex(where: { $0.fontName == font.fontName }) {
                return index
            }
            precondition(fonts.count <= Int(UInt8.max), "A layout has at most 256 fonts")
            fonts.append(font)
            return fonts.count - 1
        }
    }
}
