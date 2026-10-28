import CoreText
import Model
import Testing
import UIKit

@testable import Rendering

@Suite("Lines of a text layout")
struct TextLineTests {
    /// The texts of task 1.2 of the M8 plan, with a name for the test report.
    static let texts: [(String, String)] = [
        ("empty", ""),
        ("one line", "let x = 1"),
        ("new line at the end", "first\nsecond\n"),
        ("long word", String(repeating: "w", count: 300)),
        ("10,000 code points", longText),
        ("CJK", String(repeating: "漢字かなカナ한글 ", count: 40)),
        ("emoji", "tree 🌳 node 👩🏽‍💻 leaf 🍃 " + String(repeating: "🙂", count: 80)),
    ]

    /// A text of exactly `Limits.maxTextLength` code points, in words and lines.
    private static var longText: String {
        let unit = "reduce(into: [:]) { $0[$1, default: 0] += 1 }\n"
        let repeated = String(repeating: unit, count: Limits.maxTextLength / unit.count + 1)
        return String(repeated.unicodeScalars.prefix(Limits.maxTextLength))
    }

    @Test("The lines match the layout", arguments: texts)
    func linesMatchTheLayout(name: String, text: String) {
        let layout = TextLayout(text: text)
        let lines = TextLayout.lines(of: text)
        #expect(lines.count == layout.lineCount, "\(name)")
        for (index, line) in lines.enumerated() {
            let expected = layout.glyphs.filter { Int($0.line) == index }.map(\.glyph)
            #expect(Self.glyphs(of: line.line) == expected, "\(name), line \(index)")
        }
    }

    @Test("The ranges cover the text without a gap", arguments: texts)
    func rangesCoverTheText(name: String, text: String) throws {
        let lines = TextLayout.lines(of: text)
        var next = 0
        for line in lines {
            #expect(line.range.lowerBound == next, "\(name)")
            next = line.range.upperBound
        }
        #expect(next == text.utf16.count, "\(name)")
        let first = try #require(lines.first)
        #expect(first.range.lowerBound == 0)
    }

    @Test("The Core Text line covers the range of the line", arguments: texts)
    func lineCoversItsRange(name: String, text: String) {
        for line in TextLayout.lines(of: text) {
            let range = CTLineGetStringRange(line.line)
            let lineRange = line.range
            if lineRange.isEmpty {
                #expect(range.length == 0, "\(name)")
                continue
            }
            #expect(range.location == lineRange.lowerBound, "\(name)")
            #expect(range.length == lineRange.count, "\(name)")
        }
    }

    @Test("A wrapped text gives more than one line in the base font")
    func wrappedTextUsesTheBaseFont() throws {
        let text = String(repeating: "node ", count: 60)
        let lines = TextLayout.lines(of: text)
        #expect(lines.count > 1)
        let first = try #require(lines.first)
        let runs = CTLineGetGlyphRuns(first.line) as? [CTRun] ?? []
        let run = try #require(runs.first)
        let attributes = CTRunGetAttributes(run) as NSDictionary
        let font = try #require(attributes[NSAttributedString.Key.font] as? UIFont)
        #expect(font.fontName == TextLayout.baseFont.fontName)
        #expect(font.pointSize == TextLayout.baseFont.pointSize)
    }

    /// The glyph IDs of a Core Text line, run by run.
    private static func glyphs(of line: CTLine) -> [CGGlyph] {
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        return runs.flatMap { run in
            var ids = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &ids)
            return ids
        }
    }
}
