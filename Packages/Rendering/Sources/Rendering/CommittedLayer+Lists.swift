/// The reused lists of a committed layer. A new layer after a rotation or a leave takes the
/// lists of the layer before it with their capacity, so its first build grows no list in a
/// frame (review M9 section 3.3, item 5, m10-plan.md task 3.3).
struct LayerLists {
    var buildSlots: [Int] = []
    var buildTextIDs: [GreenItem] = []
    var textRedrawIDs: [GreenItem] = []
    var redrawSlots: [Int] = []
    var buildRedrawSlots: [Int] = []
}

extension CommittedLayer {
    /// Moves the lists out of this layer, empty and with their capacity. The layer must not be
    /// used afterward.
    func takeLists() -> LayerLists {
        LayerLists(
            buildSlots: Self.emptied(&buildSlots),
            buildTextIDs: Self.emptied(&buildTextIDs),
            textRedrawIDs: Self.emptied(&textRedrawIDs),
            redrawSlots: Self.emptied(&redrawSlots),
            buildRedrawSlots: Self.emptied(&buildRedrawSlots)
        )
    }

    /// Moves a list out, empty and with its capacity, and leaves an empty list without room.
    private static func emptied<Element>(_ list: inout [Element]) -> [Element] {
        var taken: [Element] = []
        swap(&taken, &list)
        taken.removeAll(keepingCapacity: true)
        return taken
    }

    /// Takes `lists` in place of the lists of this new layer, each one that holds more room.
    ///
    /// - Precondition: The layer has no build and no redraw yet.
    func adopt(_ lists: LayerLists) {
        precondition(build == nil && frontRedraw == nil && textRedraw == nil, "A new layer")
        if lists.buildSlots.capacity > buildSlots.capacity { buildSlots = lists.buildSlots }
        if lists.buildTextIDs.capacity > buildTextIDs.capacity { buildTextIDs = lists.buildTextIDs }
        if lists.textRedrawIDs.capacity > textRedrawIDs.capacity {
            textRedrawIDs = lists.textRedrawIDs
        }
        if lists.redrawSlots.capacity > redrawSlots.capacity { redrawSlots = lists.redrawSlots }
        if lists.buildRedrawSlots.capacity > buildRedrawSlots.capacity {
            buildRedrawSlots = lists.buildRedrawSlots
        }
    }
}
