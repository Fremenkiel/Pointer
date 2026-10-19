import Geometry

@testable import Model

/// The live content of a canvas, for the apply-then-revert test (TEST-09, D-67).
///
/// It holds the strokes, cards, and text boxes that are not erased or deleted, without the
/// `modified` values. The erase records are not part of it.
struct LiveContent: Equatable {
    /// The fields of one stroke. A stroke never changes, so the ID, the time, and the shared
    /// points tell two strokes apart.
    struct StrokeFields: Equatable {
        let created: HybridTimestamp
        let origin: Point
        let width: Float
        let points: ObjectIdentifier
    }

    /// The fields of a card or a text box without the `modified` value.
    struct NodeFields: Equatable {
        let created: HybridTimestamp
        let canvasID: CanvasID
        let position: Rect
        let text: String?
        let sortKey: FractionalIndex
    }

    let strokes: [StrokeID: StrokeFields]
    let cards: [CardID: NodeFields]
    let textBoxes: [TextBoxID: NodeFields]

    init(_ content: CanvasContent) {
        strokes = content.strokes.mapValues { stroke in
            StrokeFields(
                created: stroke.created,
                origin: stroke.origin,
                width: stroke.width,
                points: ObjectIdentifier(stroke.points)
            )
        }
        cards = content.cards.filter { !$0.value.meta.isDeleted }.mapValues { card in
            NodeFields(
                created: card.meta.created,
                canvasID: card.canvasID,
                position: card.frame,
                text: card.title,
                sortKey: card.sortKey
            )
        }
        textBoxes = content.textBoxes.filter { !$0.value.meta.isDeleted }.mapValues { box in
            NodeFields(
                created: box.meta.created,
                canvasID: box.canvasID,
                position: Rect(origin: box.origin, size: .zero),
                text: box.text,
                sortKey: box.sortKey
            )
        }
    }
}
