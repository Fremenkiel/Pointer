#!/usr/bin/env swift
import Foundation

/// The packages that rule CONTRACT-02 covers: Tier A and Tier B.
let checkedPackages = ["Geometry", "Model", "InkEngine", "Persistence", "Rendering", "Export"]

/// The minimum average number of contract checks per counted function (CONTRACT-02).
let minimumAverage = 2.0

/// A function body counts only if it has more than this number of lines (CONTRACT-02).
let minimumBodyLines = 5

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

    /// Makes a blanker for the UTF-8 bytes of one source file.
    init(source: String) { bytes = Array(source.utf8) }

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
        blank(index..<close)
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
        if isInsideString { blank(index..<index + 1) }
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
            blank(index..<open)
            stack.append(.code(isInterpolation: true, parenDepth: 0))
            index = open
        } else if starts(with: "\\" + delimiter, at: index) {
            let end = min(index + hashes + 2, bytes.count)
            blank(index..<end)
            index = end
        } else if starts(with: quote + delimiter, at: index) {
            let end = index + quote.utf8.count + hashes
            blank(index..<end)
            stack.removeLast()
            index = end
        } else {
            blank(index..<index + 1)
            index += 1
        }
    }
}

/// The result for one package.
struct PackageResult {
    /// The number of functions with more than `minimumBodyLines` lines.
    var functions = 0
    /// The number of contract checks in these functions.
    var checks = 0
}

let declarationPattern = try NSRegularExpression(
    pattern: #"(?<![.\w])(?:func\s+(?:\w+|[^\s\w(<]+)|init[?!]?|subscript)\s*"#
        + #"(?:<(?:[^<>{(]|<[^<>{(]*>)*>\s*)?\("#
)
let checkPattern = try NSRegularExpression(
    pattern: #"\b(?:precondition|preconditionFailure|assert|assertionFailure)\s*\("#
)
let guardPattern = try NSRegularExpression(pattern: #"\bguard\b[^{]*?\belse\s*\{"#)
let errorExitPattern = try NSRegularExpression(pattern: #"\bthrow\b|\breturn[ \t]+[^\s}]"#)
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

/// Counts the contract checks in one function body (CONTRACT-02).
func contractChecks(in body: String) -> Int {
    let all = NSRange(location: 0, length: (body as NSString).length)
    var count = checkPattern.numberOfMatches(in: body, range: all)
    let bytes = Array(body.utf8)
    for match in guardPattern.matches(in: body, range: all) {
        let open = match.range.location + match.range.length - 1
        guard let close = matchingBrace(in: bytes, open: open) else { continue }
        let block = NSRange(location: open, length: close - open)
        if errorExitPattern.firstMatch(in: body, range: block) != nil { count += 1 }
    }
    return count
}

/// Adds the counted functions of one source file to `result`.
func measure(source: String, into result: inout PackageResult) {
    var blanker = Blanker(source: source)
    let text = blanker.run()
    let bytes = Array(text.utf8)
    let all = NSRange(location: 0, length: (text as NSString).length)
    for match in declarationPattern.matches(in: text, range: all) {
        let start = match.range.location + match.range.length - 1
        guard let range = body(in: bytes, start: start) else { continue }
        let lines = bytes[range].filter { $0 == UInt8(ascii: "\n") }.count - 1
        guard lines > minimumBodyLines else { continue }
        result.functions += 1
        result.checks += contractChecks(in: asciiText(bytes[range]))
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
        measure(source: source, into: &result)
    }
    return result
}

let root = rootFolder()
var failures = 0
for name in checkedPackages {
    let sources = root.appendingPathComponent("Packages/\(name)/Sources")
    guard FileManager.default.fileExists(atPath: sources.path) else { continue }
    let result = measurePackage(sources)
    guard result.functions > 0 else {
        print("\(name): no functions")
        continue
    }
    let average = Double(result.checks) / Double(result.functions)
    let summary = "\(result.functions) functions, \(result.checks) checks"
    let averageText = String(format: "%.2f", average)
    if average < minimumAverage {
        failures += 1
        print("error: CONTRACT-02 \(name): \(summary), average \(averageText) is below 2.0.")
    } else {
        print("\(name): \(summary), average \(averageText)")
    }
}
exit(failures == 0 ? 0 : 1)
