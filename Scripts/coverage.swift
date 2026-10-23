#!/usr/bin/env swift
import Foundation

/// One package that rule TEST-02 covers, with its lowest line coverage in percent.
struct Limit {
    let package: String
    let minimumPercent: Double
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

/// One export of the report.
struct Export: Decodable {
    let files: [File]
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

/// Checks one package and prints its line. Returns `false` if it fails.
func check(_ limit: Limit, root: URL) -> Bool {
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
    print("\(name): \(detail)")
    return true
}

let root = rootFolder()
let failures = limits.filter { !check($0, root: root) }.count
exit(failures == 0 ? 0 : 1)
