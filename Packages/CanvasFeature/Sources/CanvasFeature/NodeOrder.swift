import Model
import os

/// A card or a text box in the drawing order of its layer: a sort key, and an ID that breaks
/// a tie of equal keys (data-model.md section 6).
protocol OrderedNode: Identifiable where ID: Comparable {
    /// The sort key of the node.
    var sortKey: FractionalIndex { get }
}

extension Card: OrderedNode {}
extension TextBox: OrderedNode {}

/// The order of the cards and the text boxes of a canvas, one helper for both kinds (review of
/// 2026-10-28, 3.4.2).
enum NodeOrder {
    /// `true` if `first` lies above `second`: a larger sort key, and the ID breaks a tie
    /// (data-model.md section 6).
    static func isAbove<Node: OrderedNode>(_ first: Node, _ second: Node) -> Bool {
        guard first.sortKey == second.sortKey else { return second.sortKey < first.sortKey }
        return second.id < first.id
    }

    /// Returns a sort key after the keys of all nodes, so that a new node is on top. If no key
    /// fits after the last one, the new node takes the last key again, and the ID breaks the
    /// tie (data-model.md section 6).
    static func nextSortKey<Node: OrderedNode>(
        above nodes: some Sequence<Node>,
        logger: Logger
    ) -> FractionalIndex {
        // The largest key without a list of all keys (PERF-01, the M10 plan task 3.6).
        let last = nodes.max { $0.sortKey < $1.sortKey }?.sortKey
        do {
            return try FractionalIndex.between(last, nil)
        } catch {
            logger.error("No sort key after the last node: \(String(describing: error))")
            return last ?? firstSortKey
        }
    }

    /// The key of the first node of a canvas: the midpoint of the empty list.
    private static var firstSortKey: FractionalIndex {
        do {
            return try FractionalIndex.between(nil, nil)
        } catch {
            preconditionFailure("The empty list has a midpoint key: \(error)")
        }
    }
}
