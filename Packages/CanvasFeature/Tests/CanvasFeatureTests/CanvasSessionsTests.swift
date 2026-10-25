import Foundation
import Model
import Testing

@testable import CanvasFeature

/// The byte budget of the sessions of the app (D-76, D-183, M-01, M-02).
@MainActor
@Suite("Canvas sessions")
struct CanvasSessionsTests {
    @Test(
        "The sessions keep their byte budget and drop the oldest steps of the oldest session",
        arguments: [0, 1]
    )
    func sessionByteBudget(over: Int) throws {
        let three = HistoryCost.bytes(ofStroke: 3)
        let four = HistoryCost.bytes(ofStroke: 4)
        let sessions = CanvasSessions(byteBudget: 4 * three + 2 * four)
        let ids = (0..<3).map { _ in CanvasID(rawValue: UUID()) }
        // Sessions of strokes of 3, 3, and 4 and 4 or 5 points: the bound, or the bound plus 17.
        for (index, id) in ids.enumerated() {
            let steps = index == 2 ? [4, 4 + over] : [3, 3]
            sessions.save(try Self.session(canvas: id, stepPoints: steps), for: id)
        }
        let full = 4 * three + 2 * four
        #expect(sessions.byteCount == (over == 0 ? full : full + 17 - three))
        #expect(sessions.session(for: ids[0]).history.undoSteps.count == (over == 0 ? 2 : 1))
        #expect(sessions.session(for: ids[2]).history.undoSteps.count == 2)
    }

    @Test("Sessions of 5 full canvases keep at most the byte budget (M-01, D-183)")
    func sessionsOfFullCanvases() throws {
        let sessions = CanvasSessions()
        let steps = Array(repeating: 300_000, count: 13)
        for _ in 0..<5 {
            let id = CanvasID(rawValue: UUID())
            sessions.save(try Self.session(canvas: id, stepPoints: steps), for: id)
        }
        let stepBytes = 20 * HistoryCost.bytes(ofStroke: 15_000)
        #expect(sessions.byteCount <= Limits.maxHistoryBytesInSessions)
        #expect(sessions.byteCount > Limits.maxHistoryBytesInSessions - stepBytes)
    }

    @Test("The history of the shown canvas counts inside the budget of all histories (D-183)")
    func shownCanvasCounts() throws {
        let three = HistoryCost.bytes(ofStroke: 3)
        let sessions = CanvasSessions(byteBudget: 6 * three)
        let ids = (0..<3).map { _ in CanvasID(rawValue: UUID()) }
        for id in ids {
            sessions.save(try Self.session(canvas: id, stepPoints: [3, 3]), for: id)
        }
        #expect(sessions.byteCount == 6 * three)
        // The canvas of `ids[2]` comes on the screen: its history still counts.
        let shown = sessions.take(for: ids[2])
        #expect(sessions.shownByteCount == shown.history.byteCount)
        // Its history grows by two steps, so the stored sessions give up two steps.
        sessions.noteShownHistory(bytes: shown.history.byteCount + 2 * three)
        #expect(sessions.byteCount + sessions.shownByteCount <= 6 * three)
        #expect(sessions.session(for: ids[0]).history.undoSteps.isEmpty)
        #expect(sessions.session(for: ids[1]).history.undoSteps.count == 2)
    }

    /// A session with one add step per entry of `stepPoints`, each of one stroke with that many
    /// points, or of shared strokes of 15,000 points for larger counts.
    private static func session(canvas: CanvasID, stepPoints: [Int]) throws -> CanvasSession {
        var content = CanvasContent(canvasID: canvas)
        var clock = HybridClock(device: Fixtures.device, wallClock: FixedWallClock())
        let shared = InkPoints(
            (0..<15_000).map { InkPoint(x: Float($0), y: 0, force: 1, time: 0) }
        )
        var history = History()
        for points in stepPoints {
            let values =
                points >= shared.count
                ? Array(repeating: shared, count: points / shared.count)
                : [InkPoints((0..<points).map { InkPoint(x: Float($0), y: 0, force: 1, time: 0) })]
            let strokes = values.map { values in
                Stroke(
                    id: StrokeID(rawValue: UUID()),
                    canvasID: canvas,
                    created: clock.now(),
                    origin: .zero,
                    width: 2,
                    points: values
                )
            }
            _ = try history.perform(AddStroke(strokes: strokes), on: &content, clock: &clock)
        }
        return CanvasSession(history: history, erased: content.erased)
    }

    @Test("A reopened canvas owns its session, and a removed session is gone (M-03)")
    func reopenAndRemove() throws {
        let sessions = CanvasSessions()
        let canvas = CanvasID(rawValue: UUID())
        sessions.save(try Self.session(canvas: canvas, stepPoints: [3]), for: canvas)
        let taken = sessions.take(for: canvas)
        #expect(taken.history.undoSteps.count == 1)
        // The first step after the reopen finds no other owner of the history.
        #expect(!sessions.hasSession(for: canvas))
        sessions.save(taken, for: canvas)
        #expect(sessions.hasSession(for: canvas))
        sessions.remove(for: canvas)
        #expect(!sessions.hasSession(for: canvas))
        #expect(sessions.count == 0)
    }
}
