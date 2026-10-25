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

    /// The most bytes that the histories of all canvases hold, the shown one included (D-76,
    /// D-183).
    let byteBudget: Int
    /// The bytes of the history of the canvas on the screen, which holds its session outside
    /// the store until it leaves (D-183).
    private(set) var shownByteCount = 0

    /// Makes an empty store.
    ///
    /// - Precondition: `byteBudget` is not negative.
    public init(byteBudget: Int = Limits.maxHistoryBytesInSessions) {
        precondition(byteBudget >= 0, "A byte budget is not negative, got \(byteBudget)")
        self.byteBudget = byteBudget
    }

    // Only the tests read it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// The number of sessions.
    var count: Int { sessions.count }
    // swiftlint:enable unused_declaration

    /// The bytes of the histories of all stored sessions.
    var byteCount: Int { sessions.values.reduce(0) { $0 + $1.history.byteCount } }

    /// Notes the bytes of the history of the canvas on the screen, and drops the oldest steps of
    /// the stored sessions until all histories fit the budget together (D-183). The shown
    /// canvas calls it after each new step. Its own history keeps its own budget.
    ///
    /// - Precondition: `bytes` is not negative.
    func noteShownHistory(bytes: Int) {
        precondition(bytes >= 0, "A history holds no negative bytes, got \(bytes)")
        shownByteCount = bytes
        fitByteBudget()
    }

    /// Returns `true` if the sessions hold the session of a canvas.
    func hasSession(for canvasID: CanvasID) -> Bool {
        sessions[canvasID] != nil
    }

    // Only the tests read it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// Returns the session of a canvas, or an empty session for a new canvas.
    func session(for canvasID: CanvasID) -> CanvasSession {
        // swiftlint:enable unused_declaration
        sessions[canvasID] ?? CanvasSession()
    }

    /// Takes the session of a canvas out, or returns an empty session for a new canvas. The
    /// canvas on the screen is then the only owner of its history, so its first step copies
    /// nothing (M-03). The canvas saves the session again when it leaves.
    func take(for canvasID: CanvasID) -> CanvasSession {
        guard let session = sessions.removeValue(forKey: canvasID) else {
            shownByteCount = 0
            return CanvasSession()
        }
        // The taken history still counts, now as the history of the shown canvas (D-183).
        shownByteCount = session.history.byteCount
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
        shownByteCount = 0
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
        // The canvas that leaves was the shown one, so its bytes are in the store now.
        shownByteCount = 0
        fitByteBudget()
        assert(order.count == sessions.count, "Each session has one place in the order")
    }

    /// Drops the oldest steps of the least recently used sessions first until the stored
    /// histories hold at most `byteBudget` less the bytes of the shown canvas. The erase records
    /// of the strokes that no kept step holds go with them (D-76).
    private func fitByteBudget() {
        let budget = max(0, byteBudget - shownByteCount)
        let start = byteCount
        var total = start
        for canvasID in order where total > budget {
            guard let index = sessions.index(forKey: canvasID) else { continue }
            let before = sessions.values[index].history.byteCount
            let target = max(0, before - (total - budget))
            let dropped = sessions.values[index].history.dropOldest(toFit: target)
            let unheld = sessions.values[index].history.unheldStrokeIDs(of: dropped)
            for id in unheld {
                sessions.values[index].erased.removeValue(forKey: id)
            }
            total -= before - sessions.values[index].history.byteCount
        }
        if total < start { logger.notice("Old undo steps are dropped to save memory.") }
        assert(total <= budget, "The sessions still pass \(budget) bytes")
    }
}
