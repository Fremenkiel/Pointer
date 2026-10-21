/// The path from the root canvas of a workspace to the current canvas (architecture.md 6.4).
///
/// The root canvas is level 0, and each card of the path adds one level (D-95). A path holds at
/// most `Limits.maxDepth` cards.
public struct NavigationPath: Hashable, Sendable {
    /// The workspace that owns the root canvas.
    public let workspace: WorkspaceID
    /// The cards from the root canvas to the current canvas, root first.
    public let cards: [CardID]

    /// Makes a path.
    ///
    /// - Throws: `ModelError.navigationPathTooLong` for more than `Limits.maxDepth` cards.
    public init(workspace: WorkspaceID, cards: [CardID] = []) throws(ModelError) {
        guard cards.count <= Limits.maxDepth else {
            throw .navigationPathTooLong(count: cards.count)
        }
        self.workspace = workspace
        self.cards = cards
    }

    /// The level of the current canvas: the count of cards. The root canvas is level 0 (D-95).
    public var level: Int { cards.count }

    /// The canvas of the last card, or the root canvas for an empty path.
    public var currentCanvas: CanvasID {
        cards.last.map(CanvasID.init) ?? CanvasID(workspace)
    }

    /// The canvas above the current canvas, or `nil` on the root canvas.
    public var parentCanvas: CanvasID? {
        guard !cards.isEmpty else { return nil }
        return cards.count == 1 ? CanvasID(workspace) : CanvasID(cards[cards.count - 2])
    }

    /// Whether "New card" may add a card here: false at level `Limits.maxDepth` (CARD-09).
    public var canAddCard: Bool { level < Limits.maxDepth }

    /// Returns the path into the child canvas of `card`.
    ///
    /// - Throws: `ModelError.depthLimitReached` at level `Limits.maxDepth`.
    public func pushing(_ card: CardID) throws(ModelError) -> NavigationPath {
        guard canAddCard else { throw .depthLimitReached }
        let pushed = try NavigationPath(workspace: workspace, cards: cards + [card])
        assert(pushed.level == level + 1, "A push adds one level")
        return pushed
    }

    /// Returns the path to the parent canvas.
    ///
    /// - Precondition: The path holds at least one card.
    public func popping() -> NavigationPath {
        precondition(!cards.isEmpty, "The root canvas has no parent")
        do {
            return try NavigationPath(workspace: workspace, cards: Array(cards.dropLast()))
        } catch {
            preconditionFailure("A shorter path is valid, got \(error)")
        }
    }
}
