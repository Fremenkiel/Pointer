import Geometry
import Testing

@testable import Model

@Suite("Text box commands")
struct TextCommandTests {
    /// Content with strokes, a card, and two text boxes, and the box that the tests change.
    private static func rig() throws -> (CommandRig, TextBox) {
        var rig = CommandRig()
        _ = try rig.load(2)
        try rig.content.add(RecordTests.card())
        let box = try RecordTests.textBox(id: Fixtures.id(30), text: "node")
        try rig.content.add(box)
        try rig.content.add(RecordTests.textBox(id: Fixtures.id(31), text: "other"))
        return (rig, box)
    }

    private static func newBox() throws -> TextBox {
        try RecordTests.textBox(id: Fixtures.id(40), text: "new", origin: Point(x: 9, y: 9))
    }

    @Test("Adding a text box and reverting the add gives back the live content")
    func addRoundTrip() throws {
        var (rig, _) = try Self.rig()
        let start = LiveContent(rig.content)
        let box = try Self.newBox()
        let command = AddTextBox(textBox: box)
        let added = try rig.apply(command)
        #expect(added.compactMap(\.textBox).map(\.id) == [box.id])
        #expect(added.compactMap(\.textBox).allSatisfy { !$0.meta.isDeleted })
        #expect(rig.content.textBoxes[box.id]?.text == "new")
        let reverted = try rig.revert(command)
        #expect(LiveContent(rig.content) == start)
        #expect(reverted.compactMap(\.textBox).map(\.meta.isDeleted) == [true])
        let redone = try rig.apply(command)
        #expect(redone.compactMap(\.textBox).map(\.meta.isDeleted) == [false])
        #expect(rig.content.textBoxes[box.id]?.text == "new")
    }

    @Test("Editing a text and reverting the edit gives back the live content")
    func editRoundTrip() throws {
        var (rig, box) = try Self.rig()
        let start = LiveContent(rig.content)
        let command = EditText(old: box, new: try box.editing(text: "changed", at: Fixtures.time))
        let edited = try rig.apply(command)
        #expect(edited.compactMap(\.textBox).map(\.text) == ["changed"])
        #expect(rig.content.textBoxes[box.id]?.text == "changed")
        let reverted = try rig.revert(command)
        #expect(LiveContent(rig.content) == start)
        #expect(reverted.compactMap(\.textBox).map(\.text) == ["node"])
    }

    @Test("Moving a text box and reverting the move gives back the live content")
    func moveRoundTrip() throws {
        var (rig, box) = try Self.rig()
        let start = LiveContent(rig.content)
        let target = Point(x: 300, y: -40)
        let command = MoveNode(from: box, to: try box.moving(to: target, at: Fixtures.time))
        let moved = try rig.apply(command)
        #expect(moved.compactMap(\.textBox).map(\.origin) == [target])
        #expect(rig.content.textBoxes[box.id]?.origin == target)
        _ = try rig.revert(command)
        #expect(LiveContent(rig.content) == start)
    }

    @Test("Deleting a text box and reverting the delete gives back the live content")
    func deleteRoundTrip() throws {
        var (rig, box) = try Self.rig()
        let start = LiveContent(rig.content)
        let command = DeleteNode(textBox: box)
        let deleted = try rig.apply(command)
        #expect(deleted.compactMap(\.textBox).map(\.meta.isDeleted) == [true])
        #expect(rig.content.textBoxes[box.id] == nil)
        let reverted = try rig.revert(command)
        #expect(LiveContent(rig.content) == start)
        #expect(reverted.compactMap(\.textBox).map(\.meta.isDeleted) == [false])
    }

    @Test("Each apply and revert gives the box a newer change time")
    func changeTimes() throws {
        var (rig, box) = try Self.rig()
        let command = EditText(old: box, new: try box.editing(text: "b", at: Fixtures.time))
        let first = try #require(try rig.apply(command).first?.textBox)
        let second = try #require(try rig.revert(command).first?.textBox)
        #expect(first.meta.modified > box.meta.modified)
        #expect(second.meta.modified > first.meta.modified)
        #expect(second.meta.created == box.meta.created)
    }

    @Test("A command on a box that is not live throws and changes nothing")
    func notLive() throws {
        var (rig, _) = try Self.rig()
        let missing = try Self.newBox()
        let before = LiveContent(rig.content)
        let commands: [any CanvasCommand] = [
            EditText(old: missing, new: try missing.editing(text: "x", at: Fixtures.time)),
            MoveNode(from: missing, to: try missing.moving(to: .zero, at: Fixtures.time)),
            DeleteNode(textBox: missing),
        ]
        for command in commands {
            #expect(throws: CommandError.textBoxNotLive(missing.id)) { try rig.apply(command) }
        }
        #expect(throws: CommandError.textBoxNotLive(missing.id)) {
            try rig.revert(AddTextBox(textBox: missing))
        }
        #expect(LiveContent(rig.content) == before)
    }

    @Test("Adding a live box again throws and changes nothing")
    func alreadyLive() throws {
        var (rig, box) = try Self.rig()
        let before = LiveContent(rig.content)
        #expect(throws: CommandError.textBoxAlreadyLive(box.id)) {
            try rig.apply(AddTextBox(textBox: box))
        }
        #expect(throws: CommandError.textBoxAlreadyLive(box.id)) {
            try rig.revert(DeleteNode(textBox: box))
        }
        #expect(LiveContent(rig.content) == before)
    }

    @Test(
        "An add takes a box below the node limit and refuses one at the limit",
        arguments: [0, 1, Limits.maxNodesPerCanvas - 1, Limits.maxNodesPerCanvas]
    )
    func nodeLimit(existing: Int) throws {
        var rig = CommandRig()
        var identifiers = IdentifierFactory(
            wallClock: FixedWallClock(millis: 1),
            random: SeededRandom(state: 9)
        )
        for _ in 0..<existing {
            try rig.content.add(RecordTests.textBox(id: identifiers.make(), text: "x"))
        }
        let command = AddTextBox(textBox: try Self.newBox())
        if existing < Limits.maxNodesPerCanvas {
            _ = try rig.apply(command)
            #expect(rig.content.nodeCount == existing + 1)
        } else {
            #expect(throws: CommandError.nodeLimitReached) { try rig.apply(command) }
            #expect(rig.content.nodeCount == existing)
        }
    }

    @Test("A text command holds the code points of its texts and no stroke (D-88)")
    func heldCost() throws {
        let box = try RecordTests.textBox(text: "abc")
        let edited = try box.editing(text: "abcdefg", at: Fixtures.time)
        #expect(AddTextBox(textBox: box).heldPointCount == 3)
        #expect(DeleteNode(textBox: box).heldPointCount == 3)
        #expect(EditText(old: box, new: edited).heldPointCount == 10)
        let moved = try box.moving(to: .zero, at: Fixtures.time)
        #expect(MoveNode(from: box, to: moved).heldPointCount == 3)
        var strokes = 0
        AddTextBox(textBox: box).forEachHeldStroke { _ in strokes += 1 }
        #expect(strokes == 0)
    }
}

extension LibraryChange {
    /// The text box of the change, or `nil` for another row.
    var textBox: TextBox? {
        guard case .textBox(let box) = self else { return nil }
        return box
    }
}
