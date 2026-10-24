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
    /// The most sessions. A canvas belongs to a workspace or to a card, so the sessions can pass
    /// the workspace limit. Past it, the session that was used least recently goes, as the
    /// camera rows of D-53 do.
    static let capacity = Limits.maxWorkspaces

    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Canvas")
    private var sessions: [CanvasID: CanvasSession] = [:]
    /// The canvases by last use, the most recent last.
    private var order: [CanvasID] = []

    /// The most control points that the histories of all sessions hold (D-76).
    let pointBudget: Int

    /// Makes an empty store.
    ///
    /// - Precondition: `pointBudget` is not negative.
    public init(pointBudget: Int = Limits.maxHistoryPointsInSessions) {
        precondition(pointBudget >= 0, "A point budget is not negative, got \(pointBudget)")
        self.pointBudget = pointBudget
    }

    /// The number of sessions.
    var count: Int { sessions.count }

    /// The control points of the histories of all sessions.
    var pointCount: Int { sessions.values.reduce(0) { $0 + $1.history.pointCount } }

    /// Returns `true` if the sessions hold the session of a canvas.
    func hasSession(for canvasID: CanvasID) -> Bool {
        sessions[canvasID] != nil
    }

    /// Returns the session of a canvas, or an empty session for a new canvas.
    func session(for canvasID: CanvasID) -> CanvasSession {
        sessions[canvasID] ?? CanvasSession()
    }

    /// Takes the session of a canvas out, or returns an empty session for a new canvas. The
    /// canvas on the screen is then the only owner of its history, so its first step copies
    /// nothing (M-03). The canvas saves the session again when it leaves.
    func take(for canvasID: CanvasID) -> CanvasSession {
        guard let session = sessions.removeValue(forKey: canvasID) else { return CanvasSession() }
        order.removeAll { $0 == canvasID }
        assert(order.count == sessions.count, "Each session has one place in the order")
        return session
    }

    /// Removes the session of a canvas whose workspace is deleted (M-03).
    public func remove(for canvasID: CanvasID) {
        sessions.removeValue(forKey: canvasID)
        order.removeAll { $0 == canvasID }
        assert(order.count == sessions.count, "Each session has one place in the order")
    }

    /// Removes all sessions, for the close of the app composition before a restore. An undo of
    /// a step of the old library would write its rows into the restored one (D-150).
    public func removeAll() {
        sessions.removeAll()
        order.removeAll()
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
        fitPointBudget()
        assert(order.count == sessions.count, "Each session has one place in the order")
    }

    /// Drops the oldest steps of the least recently used sessions first until all histories
    /// hold at most `pointBudget` control points. The erase records of the strokes that no kept
    /// step holds go with them (D-76).
    private func fitPointBudget() {
        let start = pointCount
        var total = start
        for canvasID in order where total > pointBudget {
            guard let index = sessions.index(forKey: canvasID) else { continue }
            let before = sessions.values[index].history.pointCount
            let target = max(0, before - (total - pointBudget))
            let dropped = sessions.values[index].history.dropOldest(toFit: target)
            let unheld = sessions.values[index].history.unheldStrokeIDs(of: dropped)
            for id in unheld {
                sessions.values[index].erased.removeValue(forKey: id)
            }
            total -= before - sessions.values[index].history.pointCount
        }
        if total < start { logger.notice("Old undo steps are dropped to save memory.") }
        assert(total <= pointBudget, "The sessions still pass \(pointBudget) points")
    }
}
