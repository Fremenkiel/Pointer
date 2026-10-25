#!/usr/bin/env swift
import Foundation

/// The packages that rule CONTRACT-02 covers: Tier A and Tier B.
let checkedPackages = ["Geometry", "Model", "InkEngine", "Persistence", "Rendering", "Export"]

/// A function body with more than this number of code lines needs a contract check
/// (CONTRACT-02, D-173). Blank lines and comment lines do not count, as in SwiftLint (D-176).
let maximumLinesWithoutCheck = 10

/// The comment that makes the `return` of a value in a `guard` an error exit (D-176).
let errorValueMarker = "// contract: error value"

/// Returns the text of bytes that the blanker made. They are ASCII by construction.
///
/// - Precondition: Each byte is below 0x80.
func asciiText<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
    guard let text = String(bytes: bytes, encoding: .ascii) else {
        preconditionFailure("Blanked text is not ASCII")
    }
    return text
}

/// One open context of the lexer: code, a string, or code inside a string interpolation.
enum LexerContext {
    /// Plain code, or the code of an interpolation with its open parenthesis depth.
    case code(isInterpolation: Bool, parenDepth: Int)
    /// A string literal with its number of `#` signs and its kind.
    case string(hashes: Int, isMultiline: Bool)
}

/// Replaces comments and string literals with spaces, so that later steps see only code.
///
/// Newlines stay, so line numbers do not change. Bytes outside ASCII become `x`, so that
/// byte offsets and `NSString` offsets are the same.
struct Blanker {
    private var bytes: [UInt8]
    private var stack: [LexerContext] = [.code(isInterpolation: false, parenDepth: 0)]
    private var index = 0

    /// `false` keeps the text of strings, so that only comments go. The count of code lines
    /// uses it, because a line of a multi-line string is code (D-176).
    private let blanksStrings: Bool

    /// Makes a blanker for the UTF-8 bytes of one source file.
    init(source: String, blanksStrings: Bool = true) {
        bytes = Array(source.utf8)
        self.blanksStrings = blanksStrings
    }

    /// Returns the source text with comments and strings blanked.
    mutating func run() -> String {
        while index < bytes.count {
            switch stack.last {
            case .string(let hashes, let isMultiline):
                stepString(hashes: hashes, isMultiline: isMultiline)
            default:
                stepCode()
            }
        }
        let ascii = bytes.map { $0 >= 0x80 ? UInt8(ascii: "x") : $0 }
        return asciiText(ascii)
    }

    private func starts(with text: String, at position: Int) -> Bool {
        let pattern = Array(text.utf8)
        guard position + pattern.count <= bytes.count else { return false }
        return Array(bytes[position..<position + pattern.count]) == pattern
    }

    private mutating func blankString(_ range: Range<Int>) {
        if blanksStrings { blank(range) }
    }

    private mutating func blank(_ range: Range<Int>) {
        for position in range where bytes[position] != UInt8(ascii: "\n") {
            bytes[position] = UInt8(ascii: " ")
        }
    }

    private var isInsideString: Bool { stack.count > 1 }

    private mutating func stepCode() {
        if starts(with: "//", at: index) {
            let end = bytes[index...].firstIndex(of: UInt8(ascii: "\n")) ?? bytes.count
            blank(index..<end)
            index = end
        } else if starts(with: "/*", at: index) {
            skipBlockComment()
        } else if bytes[index] == UInt8(ascii: "#") || bytes[index] == UInt8(ascii: "\"") {
            openStringIfPresent()
        } else {
            stepParenthesis()
        }
    }

    private mutating func skipBlockComment() {
        let start = index
        var depth = 0
        while index < bytes.count {
            if starts(with: "/*", at: index) {
                depth += 1
                index += 2
            } else if starts(with: "*/", at: index) {
                depth -= 1
                index += 2
                if depth == 0 { break }
            } else {
                index += 1
            }
        }
        blank(start..<index)
    }

    private mutating func openStringIfPresent() {
        var end = index
        while end < bytes.count && bytes[end] == UInt8(ascii: "#") { end += 1 }
        guard end < bytes.count, bytes[end] == UInt8(ascii: "\"") else {
            index = max(end, index + 1)
            return
        }
        let isMultiline = starts(with: "\"\"\"", at: end)
        let hashes = end - index
        let close = end + (isMultiline ? 3 : 1)
        blankString(index..<close)
        stack.append(.string(hashes: hashes, isMultiline: isMultiline))
        index = close
    }

    private mutating func stepParenthesis() {
        guard case .code(let isInterpolation, let depth) = stack.last else { return }
        let byte = bytes[index]
        if byte == UInt8(ascii: "(") {
            stack[stack.count - 1] = .code(isInterpolation: isInterpolation, parenDepth: depth + 1)
        } else if byte == UInt8(ascii: ")") && isInterpolation && depth == 0 {
            stack.removeLast()
        } else if byte == UInt8(ascii: ")") {
            stack[stack.count - 1] = .code(isInterpolation: isInterpolation, parenDepth: depth - 1)
        }
        if isInsideString { blankString(index..<index + 1) }
        index += 1
    }

    private mutating func stepString(hashes: Int, isMultiline: Bool) {
        let delimiter = String(repeating: "#", count: hashes)
        let quote = isMultiline ? "\"\"\"" : "\""
        // A single-line string cannot hold a newline. A quote that opened a "string" here was
        // part of other syntax, for example a regex literal, so the damage stops at the line end.
        if !isMultiline && bytes[index] == UInt8(ascii: "\n") {
            stack.removeLast()
            index += 1
        } else if starts(with: "\\" + delimiter + "(", at: index) {
            let open = index + hashes + 2
            blankString(index..<open)
            stack.append(.code(isInterpolation: true, parenDepth: 0))
            index = open
        } else if starts(with: "\\" + delimiter, at: index) {
            let end = min(index + hashes + 2, bytes.count)
            blankString(index..<end)
            index = end
        } else if starts(with: quote + delimiter, at: index) {
            let end = index + quote.utf8.count + hashes
            blankString(index..<end)
            stack.removeLast()
            index = end
        } else {
            blankString(index..<index + 1)
            index += 1
        }
    }
}

/// The result for one package.
struct PackageResult {
    /// The number of functions with more than `maximumLinesWithoutCheck` code lines.
    var functions = 0
    /// The number of contract checks in these functions.
    var checks = 0
    /// One line per counted function without a check, in the form of a compiler error.
    var findings: [String] = []
}

let declarationPattern = try NSRegularExpression(
    pattern: #"(?<![.\w])(?:func\s+(?:\w+|[^\s\w(<]+)|init[?!]?|subscript)\s*"#
        + #"(?:<(?:[^<>{(]|<[^<>{(]*>)*>\s*)?\("#
)
let checkPattern = try NSRegularExpression(
    pattern: #"\b(?:precondition|preconditionFailure|assert|assertionFailure)\s*\("#
)
let guardPattern = try NSRegularExpression(pattern: #"\bguard\b[^{]*?\belse\s*\{"#)
let throwPattern = try NSRegularExpression(pattern: #"\bthrow\b"#)
let valueReturnPattern = try NSRegularExpression(pattern: #"\breturn[ \t]+[^\s}]"#)
let stopWords: Set<String> = [
    "func", "init", "subscript", "var", "let", "case", "struct", "class", "enum", "protocol",
    "extension", "typealias", "associatedtype", "actor", "deinit",
]

/// Returns the offset of the brace that closes the brace at `open`.
func matchingBrace(in text: [UInt8], open: Int) -> Int? {
    var depth = 0
    for position in open..<text.count {
        if text[position] == UInt8(ascii: "{") { depth += 1 }
        if text[position] == UInt8(ascii: "}") { depth -= 1 }
        if depth == 0 { return position }
    }
    return nil
}

/// Returns the body of the declaration whose parameter list opens at `start`, or nil.
func body(in text: [UInt8], start: Int) -> Range<Int>? {
    var depth = 0
    var position = start
    while position < text.count {
        let byte = text[position]
        if byte == UInt8(ascii: "(") || byte == UInt8(ascii: "[") { depth += 1 }
        if byte == UInt8(ascii: ")") || byte == UInt8(ascii: "]") { depth -= 1 }
        if depth == 0 && byte == UInt8(ascii: "}") { return nil }
        if depth == 0 && byte == UInt8(ascii: "{") {
            return matchingBrace(in: text, open: position).map { position..<$0 }
        }
        if depth == 0 && isWordStart(text, position) && stopWords.contains(word(text, position)) {
            return nil
        }
        position += 1
    }
    return nil
}

func isIdentifierByte(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "_") || (byte >= 0x30 && byte <= 0x39)
        || (byte | 0x20 >= 0x61 && byte | 0x20 <= 0x7a)
}

func isWordStart(_ text: [UInt8], _ position: Int) -> Bool {
    isIdentifierByte(text[position]) && (position == 0 || !isIdentifierByte(text[position - 1]))
}

func word(_ text: [UInt8], _ position: Int) -> String {
    let end = text[position...].firstIndex { !isIdentifierByte($0) } ?? text.count
    return asciiText(text[position..<end])
}

/// The text of one source file after the blanker, with the facts that the count needs.
struct SourceFile {
    /// The text with comments and strings blanked.
    let text: String
    /// The bytes of `text`.
    let bytes: [UInt8]
    /// The bytes of the source with comments blanked and strings kept, at the same offsets.
    let codeBytes: [UInt8]
    /// The line numbers, from 1, of the lines with the marker of an error value.
    let markedLines: Set<Int>
    /// The offset of the first byte of each line.
    let lineStarts: [Int]

    init(source: String) {
        var blanker = Blanker(source: source)
        let blanked = blanker.run()
        let all = Array(blanked.utf8)
        let lines = source.components(separatedBy: "\n")
        var commentBlanker = Blanker(source: source, blanksStrings: false)
        text = blanked
        bytes = all
        codeBytes = Array(commentBlanker.run().utf8)
        let marked = lines.indices.filter { lines[$0].contains(errorValueMarker) }
        markedLines = Set(marked.map { $0 + 1 })
        lineStarts = [0] + all.indices.filter { all[$0] == UInt8(ascii: "\n") }.map { $0 + 1 }
    }

    /// Returns the line number, from 1, of the byte at `offset`.
    func line(of offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low + 1 < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= offset { low = middle } else { high = middle }
        }
        return low + 1
    }
}

/// Returns the bytes of `range` in `text` with the bytes of `holes` made spaces. Newlines stay.
func bytes(_ text: [UInt8], _ range: Range<Int>, without holes: [Range<Int>]) -> [UInt8] {
    var result = Array(text[range])
    for hole in holes {
        for position in hole where text[position] != UInt8(ascii: "\n") {
            result[position - range.lowerBound] = UInt8(ascii: " ")
        }
    }
    return result
}

/// Returns the number of lines inside the braces of `body` with code (D-176).
func codeLines(_ body: [UInt8]) -> Int {
    let inner = body.dropFirst().dropLast()
    return inner.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        .filter { line in line.contains { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\t") } }
        .count
}

/// Counts the contract checks in one function body (CONTRACT-02, D-176). `offset` is the offset
/// of the body in the file, for the line numbers of the markers.
func contractChecks(in body: [UInt8], offset: Int, file: SourceFile) -> Int {
    let text = asciiText(body)
    let all = NSRange(location: 0, length: body.count)
    var count = checkPattern.numberOfMatches(in: text, range: all)
    for match in guardPattern.matches(in: text, range: all) {
        let open = match.range.location + match.range.length - 1
        guard let close = matchingBrace(in: body, open: open) else { continue }
        let block = NSRange(location: open, length: close - open)
        if throwPattern.firstMatch(in: text, range: block) != nil {
            count += 1
            continue
        }
        let returns = valueReturnPattern.matches(in: text, range: block)
        let marked = returns.map { file.line(of: offset + $0.range.location) }
        if marked.contains(where: file.markedLines.contains) {
            count += 1
        }
    }
    return count
}

/// Adds the counted functions of one source file to `result`.
func measure(source: String, path: String, into result: inout PackageResult) {
    let file = SourceFile(source: source)
    let all = NSRange(location: 0, length: file.bytes.count)
    let bodies = declarationPattern.matches(in: file.text, range: all).compactMap { match in
        body(in: file.bytes, start: match.range.location + match.range.length - 1)
            .map { (declaration: match.range.location, body: $0) }
    }
    for function in bodies {
        let range = function.body.lowerBound..<(function.body.upperBound + 1)
        // A nested function counts once, as a function of its own (D-173).
        let isNested = { (other: Range<Int>) in
            other != range && range.contains(other.lowerBound)
                && other.upperBound < range.upperBound
        }
        let nested = bodies.map { $0.body.lowerBound..<($0.body.upperBound + 1) }.filter(isNested)
        let own = bytes(file.bytes, range, without: nested)
        let lines = codeLines(bytes(file.codeBytes, range, without: nested))
        guard lines > maximumLinesWithoutCheck else { continue }
        let checks = contractChecks(in: own, offset: range.lowerBound, file: file)
        result.functions += 1
        result.checks += checks
        if checks == 0 {
            let line = file.line(of: function.declaration)
            result.findings.append(
                "\(path):\(line): error: CONTRACT-02 A function of \(lines) lines "
                    + "has no contract check."
            )
        }
    }
}

/// Reads the `--root <path>` argument. The default is the current folder.
func rootFolder() -> URL {
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--root"), flag + 1 < arguments.count else {
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
    return URL(fileURLWithPath: arguments[flag + 1])
}

/// Measures all Swift files in the `Sources` folder of one package.
func measurePackage(_ folder: URL) -> PackageResult {
    var result = PackageResult()
    let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
    let files = (walker?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }
    for file in files {
        guard let source = try? String(contentsOf: file, encoding: .utf8) else {
            print("\(file.path):1: warning: CONTRACT-02 The file is not UTF-8 text. It is skipped.")
            continue
        }
        measure(source: source, path: file.path, into: &result)
    }
    return result
}

let root = rootFolder()
var failures = 0
for name in checkedPackages {
    let sources = root.appendingPathComponent("Packages/\(name)/Sources")
    guard FileManager.default.fileExists(atPath: sources.path) else { continue }
    let result = measurePackage(sources)
    for finding in result.findings { print(finding) }
    failures += result.findings.count
    guard result.functions > 0 else {
        print("\(name): no functions over \(maximumLinesWithoutCheck) lines")
        continue
    }
    // The average is a report only (D-173).
    let average = String(format: "%.2f", Double(result.checks) / Double(result.functions))
    print("\(name): \(result.functions) functions, \(result.checks) checks, average \(average)")
}
exit(failures == 0 ? 0 : 1)
