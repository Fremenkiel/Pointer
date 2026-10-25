import Testing

@testable import Model

@Suite("Navigation path")
struct NavigationPathTests {
    private static let workspace: WorkspaceID = Fixtures.id(1)

    private static func cards(_ count: Int) -> [CardID] {
        (0..<count).map { Fixtures.id(UInt8(10 + $0)) }
    }

    @Test(
        "A path holds levels 0 to 32 and refuses level 33 (D-95)",
        arguments: [0, 1, 31, Limits.maxDepth, Limits.maxDepth + 1]
    )
    func level(count: Int) throws {
        let cards = Self.cards(count)
        guard count <= Limits.maxDepth else {
            #expect(throws: ModelError.navigationPathTooLong(count: count)) {
                try NavigationPath(workspace: Self.workspace, cards: cards)
            }
            return
        }
        let path = try NavigationPath(workspace: Self.workspace, cards: cards)
        #expect(path.level == count)
        #expect(path.canAddCard == (count < Limits.maxDepth))
        #expect(path.currentCanvas == (cards.last.map(CanvasID.init) ?? CanvasID(Self.workspace)))
    }

    @Test(
        "A push adds a level below level 32 and throws at level 32",
        arguments: [0, 1, 31, Limits.maxDepth]
    )
    func push(count: Int) throws {
        let path = try NavigationPath(workspace: Self.workspace, cards: Self.cards(count))
        let card: CardID = Fixtures.id(200)
        guard count < Limits.maxDepth else {
            #expect(throws: ModelError.depthLimitReached) { try path.pushing(card) }
            return
        }
        let pushed = try path.pushing(card)
        #expect(pushed.level == count + 1)
        #expect(pushed.currentCanvas == CanvasID(card))
        #expect(pushed.popping() == path)
    }

    @Test("A pop gives the path without its last card", arguments: [1, 2, Limits.maxDepth])
    func pop(count: Int) throws {
        let cards = Self.cards(count)
        let path = try NavigationPath(workspace: Self.workspace, cards: cards)
        let popped = path.popping()
        #expect(popped.cards == Array(cards.dropLast()))
        #expect(popped.workspace == Self.workspace)
    }
}
