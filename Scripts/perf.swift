#!/usr/bin/env swift
import Foundation

// Records and compares the samples of the performance tests (D-172, D-177).
//
//   swift Scripts/perf.swift record --output <file> --commit <sha> --device <model>
//       --os <version> --xcode <version> <run>...
//   swift Scripts/perf.swift compare --baseline <file> <run>...
//
// A run is a result bundle (`.xcresult`) or a folder that `xcresulttool export attachments`
// wrote. A `.json` file holds an array of runs, for the fixtures of the self-test. The compare
// exits with 0 for a pass, 1 for a regression, and 3 if a time is more than 10 % worse with p
// from 0.01 to 0.05. Then the Makefile runs 10 more runs (D-177).

/// The file name that `PerformanceRecord` gives its attachment.
let attachmentPrefix = "perf-samples"
/// A median more than this ratio over the baseline is a regression, with p below `failP` (D-172).
let maxRatio = 1.10
/// The p below which a slower median fails (D-172).
let failP = 0.01
/// The p below which a slower median needs 10 more runs (D-177).
let unsureP = 0.05
/// The units of a time, which the compare gates. Other units are recorded (D-172).
let gatedUnits: Set<String> = ["ms", "s"]
/// The most runs on each side for the exact distribution of U. Larger sets use the normal
/// approximation.
let maxExactRuns = 40

/// One entry of the manifest that `xcresulttool export attachments` writes.
struct ManifestTest: Decodable {
    let testIdentifier: String
    let attachments: [ManifestAttachment]
}

/// One attachment of a test in the manifest.
struct ManifestAttachment: Decodable {
    let exportedFileName: String
    let suggestedHumanReadableName: String
}

/// The JSON that `PerformanceRecord` attaches.
struct SampleFile: Decodable {
    let samples: [String: Double]
}

/// The stored baseline: the values of each sample over the runs, and where they come from.
struct Baseline: Codable {
    let commit: String
    let device: String
    let os: String
    let xcode: String
    let runs: Int
    let samples: [String: [Double]]
}

/// Prints `message` and ends the script with exit code 2.
func fail(_ message: String) -> Never {
    print("error: PERF \(message)")
    exit(2)
}

/// Returns the folder of exported attachments of `run`. A result bundle is exported first.
func exportedFolder(of run: String) -> URL {
    guard run.hasSuffix(".xcresult") else { return URL(fileURLWithPath: run) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
        "xcresulttool", "export", "attachments", "--path", run, "--output-path", folder.path,
        "--filter", "\(attachmentPrefix)*",
    ]
    process.standardOutput = FileHandle.nullDevice
    do { try process.run() } catch { fail("cannot start xcresulttool: \(error)") }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fail("xcresulttool cannot export \(run)") }
    return folder
}

/// Returns the samples of one run, keyed by `<test>/<sample>`.
func samples(of run: String) -> [String: Double] {
    let folder = exportedFolder(of: run)
    let manifestURL = folder.appendingPathComponent("manifest.json")
    guard let data = try? Data(contentsOf: manifestURL),
        let tests = try? JSONDecoder().decode([ManifestTest].self, from: data)
    else { fail("\(run) has no manifest of attachments") }
    var result: [String: Double] = [:]
    for test in tests {
        for file in test.attachments
        where file.suggestedHumanReadableName.hasPrefix(attachmentPrefix) {
            let url = folder.appendingPathComponent(file.exportedFileName)
            guard let data = try? Data(contentsOf: url),
                let record = try? JSONDecoder().decode(SampleFile.self, from: data)
            else { fail("\(url.path) is not a sample file") }
            for (name, value) in record.samples { result["\(test.testIdentifier)/\(name)"] = value }
        }
    }
    return result
}

/// Returns the samples of each run of a JSON file that holds an array of runs, each a map from
/// `<test>/<sample>` to its value. The self-test fixtures use this form.
func samplesOfFile(_ path: String) -> [[String: Double]] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
        let runs = try? JSONDecoder().decode([[String: Double]].self, from: data)
    else { fail("\(path) is not an array of runs") }
    return runs
}

/// Returns the values of each sample over all runs.
func collect(_ runs: [String]) -> [String: [Double]] {
    guard !runs.isEmpty else { fail("no runs") }
    var result: [String: [Double]] = [:]
    for run in runs {
        let list = run.hasSuffix(".json") ? samplesOfFile(run) : [samples(of: run)]
        for samples in list {
            for (key, value) in samples { result[key, default: []].append(value) }
        }
    }
    return result
}

/// Returns the median of `values`.
func median(_ values: [Double]) -> Double {
    precondition(!values.isEmpty, "A median needs values")
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}

/// The U statistic of the first set, and the ties of the ranks.
struct RankSum {
    /// The U statistic of the first set.
    let u: Double
    /// `true` if two values are equal.
    let hasTies: Bool
    /// The sum of t³ - t over the groups of t equal values, for the variance of U.
    let tieTerm: Double
}

/// Returns the U statistic of `first` against `second`, with mean ranks for ties.
func rankSum(_ first: [Double], _ second: [Double]) -> RankSum {
    let all = (first.map { ($0, 0) } + second.map { ($0, 1) }).sorted { $0.0 < $1.0 }
    var ranks = [Double](repeating: 0, count: all.count)
    var start = 0
    var hasTies = false
    var tieTerm = 0.0
    while start < all.count {
        var end = start
        while end + 1 < all.count && all[end + 1].0 == all[start].0 { end += 1 }
        let size = Double(end - start + 1)
        if size > 1 { hasTies = true }
        tieTerm += size * size * size - size
        for index in start...end { ranks[index] = Double(start + end) / 2 + 1 }
        start = end + 1
    }
    let firstRanks = zip(all, ranks).filter { $0.0.1 == 0 }.reduce(0) { $0 + $1.1 }
    let count = Double(first.count)
    return RankSum(u: firstRanks - count * (count + 1) / 2, hasTies: hasTies, tieTerm: tieTerm)
}

/// Returns the number of orderings of `m` and `n` values for each U, from 0 to m × n.
func uCounts(_ m: Int, _ n: Int) -> [Double] {
    // table[i][j][u]: the orderings of i and j values with statistic u, built up by the last value.
    var table = [[[Double]]](
        repeating: [[Double]](repeating: [], count: n + 1),
        count: m + 1
    )
    for i in 0...m {
        for j in 0...n {
            var counts = [Double](repeating: 0, count: i * j + 1)
            if i == 0 || j == 0 {
                counts[0] = 1
            } else {
                for (u, value) in table[i - 1][j].enumerated() { counts[u + j] += value }
                for (u, value) in table[i][j - 1].enumerated() { counts[u] += value }
            }
            table[i][j] = counts
        }
    }
    return table[m][n]
}

/// Returns the two-sided p of the Mann-Whitney U test of `first` against `second`.
func mannWhitneyP(_ first: [Double], _ second: [Double]) -> Double {
    let rank = rankSum(first, second)
    let u = rank.u
    let m = Double(first.count)
    let n = Double(second.count)
    if !rank.hasTies && first.count <= maxExactRuns && second.count <= maxExactRuns {
        let counts = uCounts(first.count, second.count)
        let total = counts.reduce(0, +)
        let index = Int(u.rounded())
        let lower = counts[0...index].reduce(0, +) / total
        let upper = counts[index...].reduce(0, +) / total
        return min(1, 2 * min(lower, upper))
    }
    let mean = m * n / 2
    let variance = m * n / 12 * ((m + n + 1) - rank.tieTerm / ((m + n) * (m + n - 1)))
    guard variance > 0 else { return 1 }
    let z = (abs(u - mean) - 0.5) / variance.squareRoot()
    return min(1, erfc(max(z, 0) / 2.0.squareRoot()))
}

/// The result of one sample.
enum Verdict: String {
    case pass, fail, unsure, recorded, missing, new
}

/// Compares the values of one sample and returns the verdict and its line.
func judge(_ key: String, base: [Double]?, new: [Double]?) -> (Verdict, String) {
    guard let base, !base.isEmpty else { return (.new, "\(key): new, no baseline") }
    guard let new, !new.isEmpty else { return (.missing, "\(key): missing in the new runs") }
    let ratio = median(new) / median(base)
    let p = mannWhitneyP(base, new)
    let line = String(
        format: "%@: base %.4g, new %.4g, %+.1f %%, p %.2g",
        key,
        median(base),
        median(new),
        (ratio - 1) * 100,
        p
    )
    let unit = key.split(separator: ".").last.map(String.init) ?? ""
    guard gatedUnits.contains(unit) else { return (.recorded, line) }
    guard ratio > maxRatio else { return (.pass, line) }
    if p < failP { return (.fail, line) }
    return (p < unsureP ? .unsure : .pass, line)
}

/// Reads the value after `flag`.
func value(of flag: String, in arguments: [String]) -> String {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        fail("missing \(flag)")
    }
    return arguments[index + 1]
}

/// Returns the arguments that are runs: the ones after the flags and their values.
func runs(in arguments: [String], flags: [String]) -> [String] {
    var result: [String] = []
    var index = 0
    while index < arguments.count {
        if flags.contains(arguments[index]) {
            index += 2
        } else {
            result.append(arguments[index])
            index += 1
        }
    }
    return result
}

/// Writes a new baseline file from the runs.
func record(_ arguments: [String]) {
    let flags = ["--output", "--commit", "--device", "--os", "--xcode"]
    let runList = runs(in: arguments, flags: flags)
    let baseline = Baseline(
        commit: value(of: "--commit", in: arguments),
        device: value(of: "--device", in: arguments),
        os: value(of: "--os", in: arguments),
        xcode: value(of: "--xcode", in: arguments),
        runs: collect(runList).values.map(\.count).max() ?? 0,
        samples: collect(runList)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let output = URL(fileURLWithPath: value(of: "--output", in: arguments))
    do {
        try encoder.encode(baseline).write(to: output)
    } catch {
        fail("cannot write \(output.path): \(error)")
    }
    print("perf: \(baseline.samples.count) samples of \(baseline.runs) runs in \(output.path)")
}

/// Compares the runs with the baseline and exits with the result.
func compare(_ arguments: [String]) -> Never {
    let file = URL(fileURLWithPath: value(of: "--baseline", in: arguments))
    guard let data = try? Data(contentsOf: file),
        let baseline = try? JSONDecoder().decode(Baseline.self, from: data)
    else { fail("\(file.path) is not a baseline file") }
    let new = collect(runs(in: arguments, flags: ["--baseline"]))
    var counts: [Verdict: Int] = [:]
    for key in Set(baseline.samples.keys).union(new.keys).sorted() {
        let (verdict, line) = judge(key, base: baseline.samples[key], new: new[key])
        counts[verdict, default: 0] += 1
        print("\(verdict.rawValue): \(line)")
    }
    let summary = [Verdict.pass, .fail, .unsure, .missing, .recorded, .new]
        .map { "\(counts[$0] ?? 0) \($0.rawValue)" }.joined(separator: ", ")
    print("perf: \(summary)")
    if (counts[.fail] ?? 0) + (counts[.missing] ?? 0) > 0 { exit(1) }
    exit((counts[.unsure] ?? 0) > 0 ? 3 : 0)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "record": record(Array(arguments.dropFirst()))
case "compare": compare(Array(arguments.dropFirst()))
default: fail("the first argument is record or compare")
}
