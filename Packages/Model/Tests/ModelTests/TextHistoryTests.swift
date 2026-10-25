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
        let stepBytes = 2 * HistoryCost.bytes(ofText: "bbbbb")
        var history = History(byteBudget: 10 * stepBytes)
        // 9 steps of two texts of 5 bytes each take the history to 9 steps.
        _ = try Self.edit(9, codePoints: 5, history: &history, rig: &rig, box: &box)
        #expect(history.byteCount == 9 * stepBytes)
        // The last step holds texts of 5 and 5 or 5 and 6 bytes: the bound, or the bound plus one.
        let next = try box.editing(
            text: String(repeating: "c", count: 5 + over),
            at: rig.factory.clock.now()
        )
        let performed = try history.perform(
            EditText(old: box, new: next),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        #expect(history.byteCount == (over == 0 ? 10 : 9) * stepBytes + over)
        #expect(history.undoSteps.count == (over == 0 ? 10 : 9))
        #expect(performed.dropped.count == over)
    }

    @Test("500 edits of 10,000 code points keep at most the budget of one canvas (D-88, D-183)")
    func manyLargeEdits() throws {
        var rig = CommandRig()
        var box = try RecordTests.textBox(text: String(repeating: "b", count: 10_000))
        try rig.content.add(box)
        var history = History()
        _ = try Self.edit(500, codePoints: 10_000, history: &history, rig: &rig, box: &box)
        // A text of 10,000 ASCII characters takes about 10 KB, so the depth limit comes first.
        let stepBytes = 2 * HistoryCost.bytes(ofText: String(repeating: "b", count: 10_000))
        #expect(history.byteCount <= Limits.maxHistoryBytesPerCanvas)
        #expect(
            history.undoSteps.count
                == min(Limits.maxHistoryDepth, Limits.maxHistoryBytesPerCanvas / stepBytes)
        )
    }
}
