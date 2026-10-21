import Geometry
import Testing

@testable import Model

@Suite("Card commands")
struct CardCommandTests {
    /// Content with strokes, two cards, and a text box, and the card that the tests change.
    private static func rig() throws -> (CommandRig, Card) {
        var rig = CommandRig()
        _ = try rig.load(2)
        try rig.content.add(RecordTests.textBox(text: "node"))
        let frame = Rect(origin: Point(x: 10, y: 20), size: Size(width: 300, height: 210))
        let card = try RecordTests.card(id: Fixtures.id(30), frame: frame, title: "Tree")
        try rig.content.add(card)
        try rig.content.add(RecordTests.card(id: Fixtures.id(31), title: "other"))
        return (rig, card)
    }

    private static func newCard(title: String? = nil) throws -> Card {
        let frame = Rect(origin: Point(x: -500, y: 90), size: Size(width: 299, height: 209))
        return try RecordTests.card(id: Fixtures.id(40), frame: frame, title: title)
    }

    @Test("Adding a card, reverting, and adding again gives rows that match the content")
    func addRoundTrip() throws {
        var (rig, _) = try Self.rig()
        let start = LiveContent(rig.content)
        let card = try Self.newCard()
        let command = AddCard(card: card)
        let added = try rig.apply(command)
        #expect(added.compactMap(\.card) == [rig.content.cards[card.id]].compactMap { $0 })
        #expect(added.compactMap(\.card).map(\.meta.isDeleted) == [false])
        let reverted = try rig.revert(command)
        #expect(LiveContent(rig.content) == start)
        #expect(reverted.compactMap(\.card).map(\.meta.isDeleted) == [true])
        #expect(reverted.compactMap(\.card).map(\.id) == [card.id])
        let redone = try rig.apply(command)
        #expect(redone.compactMap(\.card) == [rig.content.cards[card.id]].compactMap { $0 })
        #expect(rig.content.cards[card.id]?.frame == card.frame)
    }

    @Test("Renaming a card, reverting, and renaming again gives rows that match the content")
    func renameRoundTrip() throws {
        var (rig, card) = try Self.rig()
        let start = LiveContent(rig.content)
        let command = RenameCard(old: card, new: try card.retitling("Graph", at: Fixtures.time))
        let renamed = try rig.apply(command)
        #expect(renamed.compactMap(\.card) == [rig.content.cards[card.id]].compactMap { $0 })
        #expect(rig.content.cards[card.id]?.title == "Graph")
        let reverted = try rig.revert(command)
        #expect(LiveContent(rig.content) == start)
        #expect(reverted.compactMap(\.card).map(\.title) == ["Tree"])
        let redone = try rig.apply(command)
        #expect(redone.compactMap(\.card).map(\.title) == ["Graph"])
    }

    @Test("A rename to a title of 0 code points stores no title")
    func renameToEmpty() throws {
        var (rig, card) = try Self.rig()
        let command = RenameCard(old: card, new: try card.retitling("", at: Fixtures.time))
        #expect(command.new.title == nil)
        let rows = try rig.apply(command)
        #expect(rows.compactMap(\.card).map(\.title) == [nil])
        #expect(rig.content.cards[card.id]?.title == nil)
    }

    @Test("Moving a card, reverting, and moving again gives rows that match the content")
    func moveRoundTrip() throws {
        var (rig, card) = try Self.rig()
        let start = LiveContent(rig.content)
        let target = Point(x: 1_000_000, y: -40)
        let command = MoveNode(from: card, to: try card.moving(to: target, at: Fixtures.time))
        let moved = try rig.apply(command)
        #expect(moved.compactMap(\.card) == [rig.content.cards[card.id]].compactMap { $0 })
        #expect(rig.content.cards[card.id]?.frame.origin == target)
        let reverted = try rig.revert(command)
        #expect(LiveContent(rig.content) == start)
        #expect(reverted.compactMap(\.card).map(\.frame) == [card.frame])
        _ = try rig.apply(command)
        #expect(rig.content.cards[card.id]?.frame.origin == target)
    }

    @Test("Deleting a card marks the card only, and the revert and a redo match the content")
    func deleteRoundTrip() throws {
        var (rig, card) = try Self.rig()
        let start = LiveContent(rig.content)
        let command = DeleteNode(card: card)
        let deleted = try rig.apply(command)
        #expect(deleted.count == 1)
        #expect(deleted.compactMap(\.card).map(\.meta.isDeleted) == [true])
        #expect(rig.content.cards[card.id] == nil)
        #expect(rig.content.strokes.count == 2)
        #expect(rig.content.textBoxes.count == 1)
        let reverted = try rig.revert(command)
        #expect(LiveContent(rig.content) == start)
        #expect(reverted.compactMap(\.card) == [rig.content.cards[card.id]].compactMap { $0 })
        _ = try rig.apply(command)
        #expect(rig.content.cards[card.id] == nil)
    }

    @Test("A command on a card that is not live throws and changes nothing")
    func notLive() throws {
        var (rig, _) = try Self.rig()
        let missing = try Self.newCard(title: "gone")
        let before = LiveContent(rig.content)
        let commands: [any CanvasCommand] = [
            RenameCard(old: missing, new: try missing.retitling("x", at: Fixtures.time)),
            MoveNode(from: missing, to: try missing.moving(to: .zero, at: Fixtures.time)),
            DeleteNode(card: missing),
        ]
        for command in commands {
            #expect(throws: CommandError.cardNotLive(missing.id)) { try rig.apply(command) }
        }
        #expect(throws: CommandError.cardNotLive(missing.id)) {
            try rig.revert(AddCard(card: missing))
        }
        #expect(LiveContent(rig.content) == before)
    }

    @Test("Adding a live card again throws and changes nothing")
    func alreadyLive() throws {
        var (rig, card) = try Self.rig()
        let before = LiveContent(rig.content)
        #expect(throws: CommandError.cardAlreadyLive(card.id)) {
            try rig.apply(AddCard(card: card))
        }
        #expect(throws: CommandError.cardAlreadyLive(card.id)) {
            try rig.revert(DeleteNode(card: card))
        }
        #expect(LiveContent(rig.content) == before)
    }

    @Test(
        "An add takes a card below the node limit of cards and text boxes and refuses one at it",
        arguments: [0, 1, Limits.maxNodesPerCanvas - 1, Limits.maxNodesPerCanvas]
    )
    func nodeLimit(existing: Int) throws {
        var rig = CommandRig()
        var identifiers = IdentifierFactory(
            wallClock: FixedWallClock(millis: 1),
            random: SeededRandom(state: 11)
        )
        for index in 0..<existing {
            if index.isMultiple(of: 2) {
                try rig.content.add(RecordTests.textBox(id: identifiers.make(), text: "x"))
            } else {
                try rig.content.add(RecordTests.card(id: identifiers.make()))
            }
        }
        let command = AddCard(card: try Self.newCard())
        if existing < Limits.maxNodesPerCanvas {
            _ = try rig.apply(command)
            #expect(rig.content.nodeCount == existing + 1)
        } else {
            #expect(throws: CommandError.nodeLimitReached) { try rig.apply(command) }
            #expect(rig.content.nodeCount == existing)
        }
    }

    @Test("A card command holds the code points of its titles and no stroke (D-88)")
    func heldCost() throws {
        let card = try Self.newCard(title: "abc")
        let untitled = try Self.newCard()
        #expect(AddCard(card: card).heldPointCount == 3)
        #expect(AddCard(card: untitled).heldPointCount == 0)
        #expect(DeleteNode(card: card).heldPointCount == 3)
        let renamed = try card.retitling("abcdefg", at: Fixtures.time)
        #expect(RenameCard(old: card, new: renamed).heldPointCount == 10)
        let moved = try card.moving(to: .zero, at: Fixtures.time)
        #expect(MoveNode(from: card, to: moved).heldPointCount == 3)
        var strokes = 0
        let commands: [any CanvasCommand] = [
            AddCard(card: card), RenameCard(old: card, new: renamed), DeleteNode(card: card),
            MoveNode(from: card, to: moved),
        ]
        for command in commands {
            command.forEachHeldStroke { _ in strokes += 1 }
        }
        #expect(strokes == 0)
    }

    @Test("A node reports the kind, the flag, and the canvas of its value")
    func node() throws {
        let card = try Self.newCard(title: "ab")
        let box = try RecordTests.textBox(text: "abcd")
        #expect(CanvasNode.card(card).textLength == 2)
        #expect(CanvasNode.textBox(box).textLength == 4)
        #expect(!CanvasNode.card(card).isDeleted)
        #expect(CanvasNode.textBox(box.marking(deleted: true, at: Fixtures.time)).isDeleted)
        #expect(CanvasNode.card(card).canvasID == Fixtures.canvas)
        #expect(CanvasNode.textBox(box).canvasID == Fixtures.canvas)
    }
}
