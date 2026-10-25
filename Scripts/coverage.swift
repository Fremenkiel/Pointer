#!/usr/bin/env swift
import Foundation

/// One package that rule TEST-02 covers, with its lowest line coverage in percent.
struct Limit {
    let package: String
    let minimumPercent: Double
    /// `true` for Tier A: each function that is not private has a test (TEST-02, D-174).
    var checksFunctions: Bool { minimumPercent >= 90 }
}

/// The limits of TEST-02: 90 % for Tier A and 70 % for Tier B. The tests of Rendering and Export
/// run on the iPad in PointerDeviceTests (D-77, D-120).
let limits = [
    Limit(package: "Geometry", minimumPercent: 90),
    Limit(package: "Model", minimumPercent: 90),
    Limit(package: "InkEngine", minimumPercent: 90),
    Limit(package: "Persistence", minimumPercent: 90),
    Limit(package: "Rendering", minimumPercent: 70),
    Limit(package: "Export", minimumPercent: 70),
]

/// The line counts of one file in the JSON of `llvm-cov export`.
struct Lines: Decodable {
    let count: Int
    let covered: Int
}

/// The summary of one file.
struct Summary: Decodable {
    let lines: Lines
}

/// One file of the report, with its absolute path.
struct File: Decodable {
    let filename: String
    let summary: Summary
}

/// One function of the report, with its mangled name and the number of times that it ran.
struct Function: Decodable {
    let name: String
    let count: Int
    let filenames: [String]
}

/// One export of the report. A report of `-summary-only` holds no functions.
struct Export: Decodable {
    let files: [File]
    let functions: [Function]?
}

/// The JSON of `llvm-cov export`. `swift test --enable-code-coverage` writes the same format.
struct Report: Decodable {
    let data: [Export]
}

/// Reads the `--root <path>` argument: the folder that holds `Coverage/<Package>.json`.
/// The default is `.build`, where `make coverage` writes the reports.
func rootFolder() -> URL {
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--root"), flag + 1 < arguments.count else {
        return URL(fileURLWithPath: ".build")
    }
    return URL(fileURLWithPath: arguments[flag + 1])
}

/// Returns the covered and the counted lines of the main target of `package`.
///
/// Only the files under `Sources/<Package>/` count. The report of a test run also holds the
/// generated files and the tests. Persistence has a second target, `PersistenceCrashHelper`: an
/// executable that the crash test starts as a separate process (D-54). In-process coverage
/// cannot count it, so it stays out.
func lines(of package: String, in report: Report) -> Lines {
    let folder = "/Packages/\(package)/Sources/\(package)/"
    let files = report.data.flatMap(\.files).filter { $0.filename.contains(folder) }
    let count = files.reduce(0) { $0 + $1.summary.lines.count }
    let covered = files.reduce(0) { $0 + $1.summary.lines.covered }
    return Lines(count: count, covered: covered)
}

/// The message closures of `precondition` and `assert` run only when the check fails, so no test
/// runs them. Their mangled names end in `fu_` or `fu<number>_` (D-187).
let autoclosureSuffix = try NSRegularExpression(pattern: #"fu[0-9]*_$"#)

/// Reads the allow list of `--allow <path>`, by default `coverage-allow.txt` in the root folder:
/// one mangled name per line, then `#` and the reason. Blank lines and lines that start with `#`
/// do not count (D-187).
func allowedFunctions(root: URL) -> Set<String> {
    let arguments = CommandLine.arguments
    let path =
        arguments.firstIndex(of: "--allow").flatMap {
            $0 + 1 < arguments.count ? arguments[$0 + 1] : nil
        } ?? root.appendingPathComponent("coverage-allow.txt").path
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    let names = text.split(separator: "\n").compactMap { line -> String? in
        let name =
            line.split(separator: "#", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? nil : name
    }
    return Set(names)
}

/// Returns the readable names of `mangled`, in the same order, with `swift-demangle`.
func demangled(_ mangled: [String]) -> [String] {
    // Without names, swift-demangle reads its standard input and waits.
    guard !mangled.isEmpty else { return [] }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["swift-demangle", "--compact"] + mangled
    let pipe = Pipe()
    process.standardOutput = pipe
    do { try process.run() } catch { return mangled }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard let text = String(bytes: data, encoding: .utf8) else { return mangled }
    let lines = text.split(separator: "\n").map(String.init)
    return lines.count == mangled.count ? lines : mangled
}

/// Returns the Tier A functions of `package` that no test runs, without the allowed ones.
func missedFunctions(of package: String, in report: Report, allowed: Set<String>) -> [String] {
    let folder = "/Packages/\(package)/Sources/\(package)/"
    let missed = report.data.flatMap { $0.functions ?? [] }.filter { function in
        let range = NSRange(location: 0, length: (function.name as NSString).length)
        return function.count == 0 && function.filenames.contains { $0.contains(folder) }
            && autoclosureSuffix.firstMatch(in: function.name, range: range) == nil
            && !allowed.contains(function.name)
    }
    let names = Array(Set(missed.map(\.name))).sorted()
    return zip(demangled(names), names).map { "\($0) (\($1))" }
}

/// Checks one package and prints its line. Returns `false` if it fails.
func check(_ limit: Limit, root: URL, allowed: Set<String>) -> Bool {
    let name = limit.package
    let file = root.appendingPathComponent("Coverage/\(name).json")
    guard let data = try? Data(contentsOf: file) else {
        print("error: TEST-02 \(name): no report at \(file.path). Run `make coverage`.")
        return false
    }
    guard let report = try? JSONDecoder().decode(Report.self, from: data) else {
        print("error: TEST-02 \(name): \(file.path) is not the JSON of llvm-cov export.")
        return false
    }
    let counted = lines(of: name, in: report)
    guard counted.count > 0 else {
        print("error: TEST-02 \(name): the report has no lines under Sources/\(name)/.")
        return false
    }
    let percent = 100 * Double(counted.covered) / Double(counted.count)
    let text = String(format: "%.2f %%", percent)
    let detail = "\(text) (\(counted.covered) of \(counted.count) lines)"
    guard percent >= limit.minimumPercent else {
        let minimum = String(format: "%.0f %%", limit.minimumPercent)
        print("error: TEST-02 \(name): \(detail) is below \(minimum).")
        return false
    }
    if limit.checksFunctions {
        let missed = missedFunctions(of: name, in: report, allowed: allowed)
        for function in missed { print("error: TEST-02 \(name): no test runs \(function).") }
        guard missed.isEmpty else { return false }
    }
    print("\(name): \(detail)")
    return true
}

let root = rootFolder()
let allowed = allowedFunctions(root: root)
let failures = limits.filter { !check($0, root: root, allowed: allowed) }.count
exit(failures == 0 ? 0 : 1)
