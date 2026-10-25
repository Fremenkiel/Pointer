import Foundation
import SwiftParser
import SwiftSyntax

// FLOW-04: the control flow inside a function body nests at most 3 levels (D-174, D-175).
// Usage: swift run --package-path Scripts/Nesting Nesting --root <repository>
// The tool reads the sources of each package and of the app target.

/// The most levels of control flow in a function body (FLOW-04).
let maximumDepth = 3

/// Reads the `--root <path>` argument. The default is the current folder.
func rootFolder() -> URL {
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--root"), flag + 1 < arguments.count else {
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
    return URL(fileURLWithPath: arguments[flag + 1])
}

/// Returns the folders of the sources: `Sources` of each package, and `PointerApp`.
func sourceFolders(in root: URL) -> [URL] {
    let packages = root.appendingPathComponent("Packages")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: packages.path)) ?? []
    let sources = names.sorted().map {
        packages.appendingPathComponent($0).appendingPathComponent("Sources")
    }
    return sources + [root.appendingPathComponent("PointerApp")]
}

/// Returns the findings of one file, in the form of a compiler error.
func findings(in file: URL, root: URL) -> [String] {
    guard let source = try? String(contentsOf: file, encoding: .utf8) else {
        return ["\(file.path):1: error: FLOW-04 The file is not UTF-8 text."]
    }
    let tree = Parser.parse(source: source)
    let visitor = NestingVisitor(
        converter: SourceLocationConverter(fileName: file.path, tree: tree)
    )
    visitor.walk(tree)
    return visitor.functions.filter { $0.depth > maximumDepth }.map {
        "\(file.path):\($0.line): error: FLOW-04 \($0.name) nests \($0.depth) levels deep at "
            + "line \($0.deepestLine). Move the inner part into a function of its own."
    }
}

let root = rootFolder()
var files = 0
var failures: [String] = []
for folder in sourceFolders(in: root) {
    let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
    let urls = walker?.compactMap { $0 as? URL } ?? []
    let swiftFiles = urls.filter { $0.pathExtension == "swift" }
    for file in swiftFiles.sorted(by: { $0.path < $1.path }) {
        files += 1
        failures += findings(in: file, root: root)
    }
}
for failure in failures { print(failure) }
print("nesting: \(files) files, \(failures.count) functions over \(maximumDepth) levels")
exit(failures.isEmpty ? 0 : 1)
