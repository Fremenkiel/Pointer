import Geometry
import Model
import Testing

@testable import Rendering

@Suite("Text layout")
struct TextLayoutTests {
    /// The advance of one SF Mono character at the text size.
    private static var advance: Double {
        TextLayout(text: "MM").size.width - TextLayout(text: "M").size.width
    }

    @Test("A short line is one line as wide as its characters")
    func shortLine() {
        let layout = TextLayout(text: "node")
        #expect(layout.lineCount == 1)
        #expect(layout.glyphs.count == 4)
        #expect(abs(layout.size.width - 4 * Self.advance) < 0.01)
        #expect(layout.size.height == TextLayout.lineHeight)
        #expect(layout.fontIndices.allSatisfy { $0 == 0 })
    }

    @Test("A line past the largest width wraps at a space")
    func wrapAtSpace() throws {
        let perLine = Int(TextStyle.maxWidth / Self.advance)
        let word = String(repeating: "a", count: 10)
        let words = Array(repeating: word, count: perLine / 10 + 2)
        let layout = TextLayout(text: words.joined(separator: " "))
        #expect(layout.lineCount == 2)
        #expect(layout.size.width <= TextStyle.maxWidth)
        // Each line starts with a whole word, so the first glyph of line 2 is at x = 0.
        let second = try #require(layout.glyphs.first { $0.position.y > Float(TextLayout.ascent) })
        #expect(second.position.x == 0)
    }

    @Test("A word longer than the largest width breaks inside the word")
    func longWord() {
        let perLine = Int(TextStyle.maxWidth / Self.advance)
        let layout = TextLayout(text: String(repeating: "x", count: perLine + 5))
        #expect(layout.lineCount == 2)
        #expect(layout.size.width <= TextStyle.maxWidth)
        #expect(layout.size.width > TextStyle.maxWidth - Self.advance)
    }

    @Test("An empty text and a trailing new line count an empty line", arguments: ["", "a\n"])
    func emptyLines(text: String) {
        let layout = TextLayout(text: text)
        #expect(layout.lineCount == (text.isEmpty ? 1 : 2))
        #expect(layout.size.height == Double(layout.lineCount) * TextLayout.lineHeight)
    }

    @Test("A new line starts a line, and each line sits one line height lower")
    func newLine() {
        let layout = TextLayout(text: "a\nb\nc")
        #expect(layout.lineCount == 3)
        let baselines = Set(layout.glyphs.map(\.position.y))
        #expect(baselines.count == 3)
        let first = Float(TextLayout.ascent)
        #expect(baselines.contains(first))
        #expect(baselines.contains(first + 2 * Float(TextLayout.lineHeight)))
    }

    @Test("A character that SF Mono lacks comes from a fallback font (D-84)")
    func fallback() {
        let layout = TextLayout(text: "a漢")
        #expect(layout.fonts.count == 2)
        #expect(layout.fontIndices == [0, 1])
        #expect(layout.glyphs.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
    }

    @Test("The font is SF Mono at the text size (D-15)")
    func font() {
        #expect(TextLayout.font(size: 17).pointSize == 17)
        #expect(TextLayout.font(size: 17).fontName == TextLayout(text: "a").fonts[0].fontName)
        #expect(TextLayout.lineHeight > TextStyle.fontSize)
        #expect(TextLayout.ascent > 0 && TextLayout.ascent < TextLayout.lineHeight)
    }
}
