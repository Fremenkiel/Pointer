import Geometry
import Testing

@testable import Model

@Suite("Card changes")
struct CardChangeTests {
    private static let later = HybridTimestamp(
        wallMillis: Fixtures.time.wallMillis + 1,
        counter: 0,
        device: Fixtures.device
    )

    @Test("A move sets the origin, keeps the size and the title, and sets the change time")
    func move() throws {
        let frame = Rect(origin: .zero, size: Size(width: 100, height: 70))
        let card = try RecordTests.card(frame: frame, title: "List")
        let moved = try card.moving(to: Point(x: -5, y: 9), at: Self.later)
        #expect(moved.id == card.id)
        #expect(moved.frame == Rect(origin: Point(x: -5, y: 9), size: frame.size))
        #expect(moved.title == "List")
        #expect(moved.sortKey == card.sortKey)
        #expect(moved.meta.created == card.meta.created)
        #expect(moved.meta.modified == Self.later)
    }

    @Test("A move refuses an origin that is not finite")
    func moveNotFinite() throws {
        let card = try RecordTests.card()
        #expect(throws: ModelError.invalidGeometry(reason: "card frame is not finite")) {
            try card.moving(to: Point(x: .nan, y: 0), at: Self.later)
        }
    }

    @Test(
        "A new title takes 0, 1, and the limit of code points and refuses the limit plus one",
        arguments: [0, 1, Limits.maxTitleLength, Limits.maxTitleLength + 1]
    )
    func retitleLength(length: Int) throws {
        let card = try RecordTests.card(title: "old")
        let title = String(repeating: "a", count: length)
        if length <= Limits.maxTitleLength {
            let retitled = try card.retitling(title, at: Self.later)
            #expect(retitled.title == title)
            #expect(retitled.frame == card.frame)
            #expect(retitled.meta.modified == Self.later)
        } else {
            #expect(throws: ModelError.invalidTitle(length: length)) {
                try card.retitling(title, at: Self.later)
            }
        }
    }

    @Test("A new title can be none and refuses U+0000 (D-57)")
    func retitleNoneAndNull() throws {
        let card = try RecordTests.card(title: "old")
        #expect(try card.retitling(nil, at: Self.later).title == nil)
        #expect(throws: ModelError.nullCharacter) {
            try card.retitling("a\u{0}b", at: Self.later)
        }
    }

    @Test("A mark sets and clears the tombstone flag", arguments: [true, false])
    func mark(isDeleted: Bool) throws {
        let card = try RecordTests.card(title: "card")
        let marked = card.marking(deleted: isDeleted, at: Self.later)
        #expect(marked.meta.isDeleted == isDeleted)
        #expect(marked.meta.modified == Self.later)
        #expect(marked.meta.created == card.meta.created)
        #expect(marked.title == "card")
    }

    @Test("A replace changes the live card and returns the card before it")
    func replace() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        let card = try RecordTests.card(title: "old")
        try content.add(card)
        let earlier = content.replace(try card.retitling("new", at: Self.later))
        #expect(earlier == card)
        #expect(content.cards[card.id]?.title == "new")
        #expect(content.cards.count == 1)
    }

    @Test("A removed card leaves the content, and an add puts it back")
    func removeAndAdd() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        let card = try RecordTests.card()
        try content.add(card)
        #expect(content.removeCard(card.id) == card)
        #expect(content.cards.isEmpty)
        #expect(content.nodeCount == 0)
        try content.add(card)
        #expect(content.cards[card.id] == card)
    }

    @Test("A change of a live card returns its row, and a card that is not live is refused")
    func change() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        let card = try RecordTests.card()
        let moved = try card.moving(to: Point(x: 3, y: 4), at: Self.later)
        #expect(throws: CommandError.cardNotLive(card.id)) {
            try content.change(to: moved, at: Self.later)
        }
        try content.add(card)
        let row = try content.change(to: moved, at: Self.later)
        #expect(row.card == moved)
        #expect(content.cards[card.id] == moved)
    }

    @Test("A bury returns the tombstone, and a revive puts the card back as a live card")
    func buryAndRevive() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        let card = try RecordTests.card()
        try content.add(card)
        let tombstone = try content.bury(card.id, at: Self.later)
        #expect(tombstone.card == card.marking(deleted: true, at: Self.later))
        #expect(content.cards.isEmpty)
        #expect(throws: CommandError.cardNotLive(card.id)) {
            try content.bury(card.id, at: Self.later)
        }
        let live = try content.revive(card, at: Self.later)
        #expect(live.card == card.marking(deleted: false, at: Self.later))
        #expect(throws: CommandError.cardAlreadyLive(card.id)) {
            try content.revive(card, at: Self.later)
        }
    }

    @Test(
        "A revive takes a card up to the node limit of cards and text boxes and refuses one more",
        arguments: [0, 1, Limits.maxNodesPerCanvas - 1, Limits.maxNodesPerCanvas]
    )
    func reviveAtNodeLimit(existing: Int) throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        var identifiers = IdentifierFactory(
            wallClock: FixedWallClock(millis: 1),
            random: SeededRandom(state: 7)
        )
        for index in 0..<existing {
            if index.isMultiple(of: 2) {
                try content.add(RecordTests.card(id: identifiers.make()))
            } else {
                try content.add(RecordTests.textBox(id: identifiers.make(), text: "x"))
            }
        }
        let card = try RecordTests.card(id: identifiers.make())
        if existing < Limits.maxNodesPerCanvas {
            _ = try content.revive(card, at: Self.later)
            #expect(content.nodeCount == existing + 1)
        } else {
            #expect(throws: CommandError.nodeLimitReached) {
                try content.revive(card, at: Self.later)
            }
            #expect(content.nodeCount == existing)
        }
    }
}

extension LibraryChange {
    /// The card of the change, or `nil` for another row.
    var card: Card? {
        guard case .card(let card) = self else { return nil }
        return card
    }
}
