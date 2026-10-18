import os

/// The signpost intervals of the hot paths of the renderer (PERF-03).
///
/// `OSSignposter.beginInterval` makes an `OSSignpostIntervalState` object for each interval,
/// also when nothing records: 3 heap allocations per interval on the device. `os_signpost`
/// with an `OSLog` makes none (PERF-01, docs/m2-fix-plan.md, phase 5, task 7). The intervals
/// keep their names, so Instruments shows them as before.
enum RenderSignpost {
    /// The log of the intervals: the subsystem and the category of the renderer.
    static let log = OSLog(subsystem: "dk.saarikivi.pointer", category: "Rendering")

    /// Begins the interval `name`. One interval of a name runs at a time.
    static func begin(_ name: StaticString) {
        os_signpost(.begin, log: log, name: name)
    }

    /// Ends the interval `name`.
    static func end(_ name: StaticString) {
        os_signpost(.end, log: log, name: name)
    }
}
