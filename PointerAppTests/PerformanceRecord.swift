import Foundation
import XCTest

/// The samples of one performance test, for `make perf-baseline` and `make perf-compare`
/// (D-172, D-177).
///
/// The test attaches its samples as one JSON file to the result bundle. `Scripts/perf.swift`
/// reads the files of each run. A sample name ends with its unit. The compare gates a time
/// (`.ms` or `.s`) and records a memory size (`.mb`) or a count (`.count`) without a gate. Each
/// test reports the median of its own repetitions as one sample, because the spread that the
/// compare needs comes from separate runs (D-177).
enum PerformanceRecord {
    /// The file name of the attachment that `Scripts/perf.swift` looks for.
    static let attachmentName = "perf-samples.json"
    /// The units that a sample name can end with.
    static let units = ["ms", "s", "mb", "count"]

    /// Attaches `samples` to the result of the running test, in an activity named `line`.
    ///
    /// - Precondition: Each name ends with a unit of `units`, and each value is finite.
    static func attach(_ samples: [String: Double], line: String = "performance samples") {
        precondition(!samples.isEmpty, "A record holds at least one sample")
        for (name, value) in samples {
            let unit = name.split(separator: ".").last.map(String.init) ?? ""
            precondition(units.contains(unit), "Sample \(name) has no known unit")
            precondition(value.isFinite, "Sample \(name) is \(value)")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(["samples": samples]) else {
            preconditionFailure("Finite samples always encode")
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = attachmentName
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: line) { $0.add(attachment) }
    }

    /// Returns the median of `values`, or `nil` for no values.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
