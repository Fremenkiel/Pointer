import Foundation
import Model
import Testing

@testable import CanvasFeature

/// The point budget of the sessions of the app (D-76, M-01, M-02).
@MainActor
@Suite("Canvas sessions")
struct CanvasSessionsTests {
    @Test(
        "The sessions keep their point budget and drop the oldest steps of the oldest session",
        arguments: [0, 1]
    )
    func sessionPointBudget(over: Int) throws {
        let sessions = CanvasSessions(pointBudget: 20)
        let ids = (0..<3).map { _ in CanvasID(rawValue: UUID()) }
        // Sessions of 6, 6, and 8 or 9 points: the bound, or the bound plus one.
        for (index, id) in ids.enumerated() {
            let steps = index == 2 ? [4, 4 + over] : [3, 3]
            sessions.save(try Self.session(canvas: id, stepPoints: steps), for: id)
        }
        #expect(sessions.pointCount == (over == 0 ? 20 : 18))
        #expect(sessions.session(for: ids[0]).history.undoSteps.count == (over == 0 ? 2 : 1))
        #expect(sessions.session(for: ids[2]).history.undoSteps.count == 2)
    }

    @Test("Sessions of 5 full canvases keep at most 16,000,000 points (M-01)")
    func sessionsOfFullCanvases() throws {
        let sessions = CanvasSessions()
        let steps = Array(repeating: 300_000, count: 13)
        for _ in 0..<5 {
            let id = CanvasID(rawValue: UUID())
            sessions.save(try Self.session(canvas: id, stepPoints: steps), for: id)
        }
        #expect(sessions.pointCount <= Limits.maxHistoryPointsInSessions)
        #expect(sessions.pointCount > Limits.maxHistoryPointsInSessions - 300_000)
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
