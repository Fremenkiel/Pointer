import Foundation
import Geometry
import Model
import Testing

@testable import Persistence

@Suite("Validation of a stored navigation path (D-112)")
struct PathValidationTests {
    private static let workspace = WorkspaceID(rawValue: UUID())

    /// The IDs of a chain of `count` cards, each in the canvas of the card before it.
    private static func chain(_ count: Int) -> [CardID] {
        (0..<count).map { _ in CardID(rawValue: UUID()) }
    }

    private static func card(
        _ id: CardID,
        in parent: CanvasID,
        isDeleted: Bool = false
    ) throws -> Card {
        try Card(
            id: id,
            meta: RecordMeta(created: Values.early, modified: Values.late, isDeleted: isDeleted),
            canvasID: parent,
            frame: Rect(origin: .zero, size: Size(width: 64, height: 48)),
            title: nil,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    /// The rows of a chain, root first. `deleted` names the index of a tombstone.
    private static func rows(_ chain: [CardID], deleted: Int? = nil) throws -> [LibraryChange] {
        var parent = CanvasID(workspace)
        var rows: [LibraryChange] = []
        for (index, id) in chain.enumerated() {
            rows.append(.card(try card(id, in: parent, isDeleted: index == deleted)))
            parent = CanvasID(id)
        }
        return rows
    }

    @Test("An empty path stays empty")
    func empty() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let path = try await repository.validPath([], in: Self.workspace)
        #expect(path == (try NavigationPath(workspace: Self.workspace)))
    }

    @Test("A path takes the cards that still wait for the save")
    func pendingCards() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let chain = Self.chain(2)
        let rows = try Self.rows(chain)
        // The first send saves at once. The next one waits for the save interval.
        try await repository.send([rows[0]])
        try await repository.send([rows[1]])
        #expect(await repository.pendingCount == 1)
        let path = try await repository.validPath(chain, in: Self.workspace)
        #expect(path.cards == chain)
        #expect(await repository.pendingCount == 0)
    }

    @Test("The initializer of the app opens a library and keeps its rows")
    func appInitializer() async throws {
        let harness = try RepositoryHarness()
        let repository = harness.makeAsTheApp()
        _ = try await repository.open { _ in }
        let chain = Self.chain(1)
        try await repository.send(try Self.rows(chain))
        try await repository.saveNow()
        let path = try await repository.validPath(chain, in: Self.workspace)
        #expect(path.cards == chain)
    }

    @Test("A valid path of 32 cards stays whole")
    func full() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let chain = Self.chain(Limits.maxDepth)
        try await repository.send(try Self.rows(chain))
        try await repository.saveNow()
        let path = try await repository.validPath(chain, in: Self.workspace)
        #expect(path.cards == chain)
        #expect(path.level == Limits.maxDepth)
    }

    @Test("A deleted card in the middle cuts the path before it")
    func deletedCard() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let chain = Self.chain(5)
        try await repository.send(try Self.rows(chain, deleted: 2))
        let path = try await repository.validPath(chain, in: Self.workspace)
        #expect(path.cards == Array(chain.prefix(2)))
    }

    @Test("A card under a different parent cuts the path before it")
    func wrongParent() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let chain = Self.chain(4)
        var rows = try Self.rows(Array(chain.prefix(2)))
        rows.append(.card(try Self.card(chain[2], in: CanvasID(chain[0]))))
        rows.append(.card(try Self.card(chain[3], in: CanvasID(chain[2]))))
        try await repository.send(rows)
        try await repository.saveNow()
        let path = try await repository.validPath(chain, in: Self.workspace)
        #expect(path.cards == Array(chain.prefix(2)))
    }

    @Test("A first card of another workspace and a missing card give an empty path")
    func otherWorkspace() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let chain = Self.chain(2)
        try await repository.send(try Self.rows(chain))
        try await repository.saveNow()
        let other = WorkspaceID(rawValue: UUID())
        #expect(try await repository.validPath(chain, in: other).cards.isEmpty)
        let missing = [CardID(rawValue: UUID())] + chain
        #expect(try await repository.validPath(missing, in: Self.workspace).cards.isEmpty)
    }

    @Test("A path of 33 cards from a damaged file keeps its first 32 valid cards")
    func tooLong() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let chain = Self.chain(Limits.maxDepth + 1)
        try await repository.send(try Self.rows(chain))
        try await repository.saveNow()
        let path = try await repository.validPath(chain, in: Self.workspace)
        #expect(path.cards == Array(chain.prefix(Limits.maxDepth)))
    }
}
