import Model
import os

/// The undo history and the erase records of one canvas for the time the app runs (D-12).
public struct CanvasSession: Sendable {
    /// The undo and redo steps.
    public var history = History()
    /// The erase records of the session. A new load of the canvas does not read them, so the
    /// session keeps them for the undo steps (data-model.md section 8).
    public var erased: [StrokeID: EraseRecord] = [:]

    /// Makes an empty session.
    public init() {}
}

/// The sessions of all canvases that the app opened while it runs (D-12). `PointerApp` holds
/// it, so a workspace switch keeps the history of each canvas.
@MainActor
public final class CanvasSessions {
    /// The most sessions. In M4 each canvas belongs to a workspace, so the workspace limit
    /// bounds them. Past it, the session that was used least recently goes.
    static let capacity = Limits.maxWorkspaces

    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Canvas")
    private var sessions: [CanvasID: CanvasSession] = [:]
    /// The canvases by last use, the most recent last.
    private var order: [CanvasID] = []

    /// Makes an empty store.
    public init() {}

    /// The number of sessions.
    var count: Int { sessions.count }

    /// Returns the session of a canvas, or an empty session for a new canvas.
    func session(for canvasID: CanvasID) -> CanvasSession {
        sessions[canvasID] ?? CanvasSession()
    }

    /// Keeps the session of a canvas and marks the canvas as the most recent one.
    func save(_ session: CanvasSession, for canvasID: CanvasID) {
        if sessions[canvasID] == nil, sessions.count == Self.capacity, let oldest = order.first {
            sessions[oldest] = nil
            order.removeFirst()
            logger.notice("The undo history of the least recently used canvas is dropped.")
        }
        sessions[canvasID] = session
        order.removeAll { $0 == canvasID }
        order.append(canvasID)
        assert(order.count == sessions.count, "Each session has one place in the order")
    }
}
