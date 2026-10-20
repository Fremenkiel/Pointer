import Testing

@testable import Model

@Suite("Text in the history budget")
struct TextHistoryTests {
    /// Performs `EditText` steps on one box, each from a text of `count` code points to another
    /// one, and returns the result of the last step.
    private static func edit(
        _ steps: Int,
        codePoints count: Int,
        history: inout History,
        rig: inout CommandRig,
        box: inout TextBox
    ) throws -> History.Performed? {
        var last: History.Performed?
        for step in 0..<steps {
            let letter = step.isMultiple(of: 2) ? "a" : "b"
            let next = try box.editing(
                text: String(repeating: letter, count: count),
                at: rig.factory.clock.now()
            )
            last = try history.perform(
                EditText(old: box, new: next),
                on: &rig.content,
                clock: &rig.factory.clock
            )
            box = try #require(rig.content.textBoxes[box.id])
        }
        return last
    }

    @Test(
        "Text steps count against the point budget, and the oldest step goes past it (D-88)",
        arguments: [0, 1]
    )
    func budget(over: Int) throws {
        var rig = CommandRig()
        var box = try RecordTests.textBox(text: String(repeating: "b", count: 5))
        try rig.content.add(box)
        var history = History(pointBudget: 100)
        // 9 steps of 5 + 5 code points take the history to 90.
        _ = try Self.edit(9, codePoints: 5, history: &history, rig: &rig, box: &box)
        #expect(history.pointCount == 90)
        // The last step adds 5 + 5 or 5 + 6 code points: the bound, or the bound plus one.
        let next = try box.editing(
            text: String(repeating: "c", count: 5 + over),
            at: rig.factory.clock.now()
        )
        let performed = try history.perform(
            EditText(old: box, new: next),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        #expect(history.pointCount == (over == 0 ? 100 : 91))
        #expect(history.undoSteps.count == (over == 0 ? 10 : 9))
        #expect(performed.dropped.count == over)
    }

    @Test("500 edits of 10,000 code points keep at most the budget of one canvas (D-88)")
    func manyLargeEdits() throws {
        var rig = CommandRig()
        var box = try RecordTests.textBox(text: String(repeating: "b", count: 10_000))
        try rig.content.add(box)
        var history = History()
        _ = try Self.edit(500, codePoints: 10_000, history: &history, rig: &rig, box: &box)
        #expect(history.pointCount <= Limits.maxHistoryPointsPerCanvas)
        #expect(history.undoSteps.count == Limits.maxHistoryPointsPerCanvas / 20_000)
    }
}
