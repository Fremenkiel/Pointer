import os

/// The signpost intervals of the hot paths of the canvas (PERF-03). Like `RenderSignpost`, it
/// uses `os_signpost` with an `OSLog`, which allocates nothing.
enum CanvasSignpost {
    /// The log of the intervals: the subsystem and the category of the canvas.
    static let log = OSLog(subsystem: "dk.saarikivi.pointer", category: "Canvas")

    /// Begins the interval `name`. One interval of a name runs at a time.
    static func begin(_ name: StaticString) {
        os_signpost(.begin, log: log, name: name)
    }

    /// Ends the interval `name`.
    static func end(_ name: StaticString) {
        os_signpost(.end, log: log, name: name)
    }
}
