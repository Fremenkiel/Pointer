import Geometry
import Model
import UIKit

/// The cards of the canvas screen (architecture.md 5.5 and 6).
extension CanvasViewController {
    /// Gives the loaded strokes and cards to the renderer. The renderer lays out the card titles
    /// off the render thread, so the first frame does not wait for them (D-92).
    func loadRenderer() {
        renderer.load(Array(content.strokes.values))
        renderer.load(Array(content.cards.values))
    }

    /// Notes a long press that began beside the text boxes: on a card, the start of a move or
    /// of its menu (CARD-07, CARD-08), and on empty canvas the menu of "New card". Ink does not
    /// count (D-113). A running edit ends first.
    func beginCardPress(at point: Point) {
        endTextEdit()
        textEditing.menuBox = nil
        textEditing.menuCard = nil
        textEditing.menuPoint = nil
        guard let card = card(at: point) else {
            textEditing.menuPoint = point
            return
        }
        textEditing.cardMove = TextEditing.CardMove(card: card, start: point, current: card)
    }

    /// Moves the card with the finger. The renderer shows it at the new place.
    func continueCardMove(to point: Point) {
        guard var move = textEditing.cardMove else { return }
        let target = Point(
            x: move.card.frame.minX + point.x - move.start.x,
            y: move.card.frame.minY + point.y - move.start.y
        )
        guard let moved = try? move.card.moving(to: target, at: move.card.meta.modified) else {
            logger.error("A moved card has a frame that is not finite")
            return
        }
        move.current = moved
        textEditing.cardMove = move
        renderer.changeCards(removing: [], adding: [moved])
    }

    /// Ends a long press beside the text boxes: a move of a card records one step, a card that
    /// did not move opens its menu, and empty canvas opens the menu of "New card".
    func endCardPress(at location: CGPoint) {
        if let move = textEditing.cardMove {
            textEditing.cardMove = nil
            guard move.current.frame.origin != move.card.frame.origin else {
                textEditing.menuCard = move.card
                presentMenu(at: location)
                return
            }
            applyCardStep(MoveNode(from: move.card, to: move.current), shows: move.card.id)
            return
        }
        guard textEditing.menuPoint != nil else { return }
        presentMenu(at: location)
    }

    /// Puts a moved card back at its place before the move.
    func cancelCardMove() {
        textEditing.menuPoint = nil
        guard let move = textEditing.cardMove else { return }
        textEditing.cardMove = nil
        renderer.changeCards(removing: [], adding: [move.card])
    }

    private func presentMenu(at location: CGPoint) {
        textEditing.menu?.presentEditMenu(
            with: UIEditMenuConfiguration(identifier: nil, sourcePoint: location)
        )
    }

    /// The menu of a long press on a card without a drag: "Rename" and "Delete" (CARD-08).
    func cardMenu(for card: Card) -> UIMenu {
        let rename = UIAction(title: CanvasStrings.rename) { [weak self] _ in
            self?.showRenameAlert(for: card.id)
        }
        let deleteHandler: UIActionHandler = { [weak self] _ in self?.deleteCard(card.id) }
        let delete = UIAction(
            title: CanvasStrings.delete,
            attributes: .destructive,
            handler: deleteHandler
        )
        return UIMenu(children: [rename, delete])
    }

    /// Makes the rename alert of a card: a text field with the title, as the workspace rename
    /// does (D-101).
    func renameAlert(for id: CardID) -> UIAlertController {
        let alert = UIAlertController(
            title: CanvasStrings.rename,
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { [title = content.cards[id]?.title] field in
            field.text = title
            field.placeholder = CanvasStrings.titlePlaceholder
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: CanvasStrings.cancel, style: .cancel))
        let handler: (UIAlertAction) -> Void = { [weak self, weak alert] _ in
            self?.renameCard(id, to: alert?.textFields?.first?.text)
        }
        alert.addAction(
            UIAlertAction(title: CanvasStrings.rename, style: .default, handler: handler)
        )
        return alert
    }

    private func showRenameAlert(for id: CardID) {
        textEditing.menuCard = nil
        present(renameAlert(for: id), animated: true)
    }

    /// Gives a card a new title with one step. A title of 0 code points stores no title, a
    /// title that did not change records no step, and a title above `Limits.maxTitleLength`
    /// code points shows a message (CARD-08, D-57).
    func renameCard(_ id: CardID, to title: String?) {
        guard let card = content.cards[id] else { return }
        let renamed: Card
        do {
            renamed = try card.retitling(title, at: clock.now())
        } catch {
            onMessage(CanvasStrings.titleLimit)
            return
        }
        guard renamed.title != card.title else { return }
        applyCardStep(RenameCard(old: card, new: renamed), shows: id)
    }

    /// Deletes a card with one step. Its child content stays (D-18).
    func deleteCard(_ id: CardID) {
        textEditing.menuCard = nil
        guard let card = content.cards[id] else { return }
        applyCardStep(DeleteNode(card: card), shows: id)
    }

    /// Performs a card step, sends its rows, and shows the card as the content holds it.
    private func applyCardStep(_ command: any CanvasCommand, shows id: CardID) {
        do {
            send(try perform(command))
        } catch {
            logger.error("A card step did not apply: \(String(describing: error))")
        }
        if let shown = content.cards[id] {
            renderer.changeCards(removing: [], adding: [shown])
        } else {
            renderer.changeCards(removing: [id], adding: [])
        }
    }

    /// The menu of a long press on empty canvas: "New card" (CARD-01).
    func newCardMenu(at point: Point) -> UIMenu {
        let handler: UIActionHandler = { [weak self] _ in self?.addCard(at: point) }
        return UIMenu(children: [UIAction(title: CanvasStrings.newCard, handler: handler)])
    }

    /// Returns the card under a canvas point, the one with the largest sort key on top, or `nil`.
    func card(at point: Point) -> Card? {
        precondition(point.isFinite, "A hit test needs a finite point")
        var best: Card?
        for card in content.cards.values where card.frame.contains(point) {
            if best.map({ Self.isAbove($0, card) }) ?? false { continue }
            best = card
        }
        return best
    }

    /// `true` if `first` lies above `second`: a larger sort key, and the ID breaks a tie
    /// (data-model.md section 6).
    private static func isAbove(_ first: Card, _ second: Card) -> Bool {
        guard first.sortKey == second.sortKey else { return second.sortKey < first.sortKey }
        return first.id.rawValue.uuidString > second.id.rawValue.uuidString
    }

    /// Adds a new card at a canvas point with one undo step (CARD-01, D-101). At level 32 and at
    /// the node limit, it shows a message and adds nothing (CARD-09, D-95).
    func addCard(at point: Point) {
        textEditing.menuPoint = nil
        guard level < Limits.maxDepth else {
            onMessage(CanvasStrings.depthLimit)
            return
        }
        guard content.nodeCount < Limits.maxNodesPerCanvas else {
            onMessage(CanvasStrings.nodeLimit)
            return
        }
        do {
            let card = try Card(
                id: clock.makeIdentifier(CardID.self),
                meta: RecordMeta(created: clock.now()),
                canvasID: content.canvasID,
                frame: Card.defaultFrame(at: point, camera: renderer.camera, viewSize: viewSize),
                title: nil,
                sortKey: nextCardSortKey()
            )
            send(try perform(AddCard(card: card)))
            renderer.changeCards(removing: [], adding: [card])
            assert(content.cards[card.id] != nil, "The new card is live")
        } catch CommandError.nodeLimitReached {
            onMessage(CanvasStrings.nodeLimit)
        } catch {
            logger.error("A new card did not apply: \(String(describing: error))")
        }
    }

    /// The sort key after the last card: a new card lies above the others.
    private func nextCardSortKey() -> FractionalIndex {
        let last = content.cards.values.map(\.sortKey).max()
        do {
            return try FractionalIndex.between(last, nil)
        } catch {
            // The ID breaks the tie of two equal keys (data-model.md section 6).
            logger.error("No sort key after the last card: \(String(describing: error))")
            return last ?? Self.firstCardSortKey
        }
    }

    /// The key of the first card of a canvas: the midpoint of the empty list.
    private static var firstCardSortKey: FractionalIndex {
        do {
            return try FractionalIndex.between(nil, nil)
        } catch {
            preconditionFailure("The empty list has a midpoint: \(error)")
        }
    }

    /// Returns the card that a double tap at a canvas point opens: a card that no text box
    /// covers there (D-100), or `nil`.
    func openableCard(at point: Point) -> Card? {
        guard point.isFinite, textBox(at: point) == nil else { return nil }
        return card(at: point)
    }

    /// Opens the card under a finger double tap (CARD-03, D-09). A running edit ends first.
    @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        openCard(at: canvasPoint(of: recognizer))
    }

    /// Opens the card at a canvas point that no text box covers. A running edit ends first.
    func openCard(at point: Point) {
        guard let card = openableCard(at: point) else { return }
        endTextEdit()
        onOpenCard(card)
    }

    /// `true` if a finger tap at a canvas point waits for the double tap: only on a card that no
    /// text box covers (D-100).
    func fingerTapWaits(at point: Point) -> Bool {
        openableCard(at: point) != nil
    }

    /// Logs the wait of a single tap from the finger lift, for the measure of the delay of a
    /// tap on a card (m6-plan.md task 4.3). The log holds a number only, no content.
    func logTapWait() {
        guard let lift = textEditing.fingerTap.liftTime else { return }
        let wait = (CACurrentMediaTime() - lift) * 1_000
        let onCard = openableCard(at: canvasPoint(of: textEditing.fingerTap)) != nil
        logger.info("Tap wait \(wait, format: .fixed(precision: 1)) ms, on a card: \(onCard)")
    }

    /// Starts the open of a card (architecture.md 6.2, D-98): the camera flies until the card
    /// covers the screen at the scale k = max(W / w, H / h), and the parent fades out under the
    /// card. Input is off until the end, so a second double tap does nothing. `onEnd` runs once
    /// at the end of the flight.
    public func beginOpen(of card: Card, onEnd: @escaping @MainActor () -> Void) {
        guard cardTransition == nil, viewSize.width > 0, viewSize.height > 0 else { return }
        endTextEdit()
        canvasView.isUserInteractionEnabled = false
        cardTransition = CardTransition(kind: .open, start: camera, onEnd: onEnd)
        renderer.beginOpen(of: card.id)
        cameraController.fly(to: Self.coverCamera(of: card.frame, viewSize: viewSize))
        canvasView.inkView.requestFrame()
        assert(cameraController.flightProgress != nil, "The open flies")
    }

    /// Ends an open or a leave that cannot finish, for example when the child does not load:
    /// the parent shows again at its camera before the flight, and input is on again.
    public func cancelCardTransition() {
        let start = cardTransition?.start
        cardTransition = nil
        renderer.endTransition()
        if let start { cameraController.fly(to: start) }
        canvasView.isUserInteractionEnabled = true
        canvasView.inkView.requestFrame()
    }

    /// `true` while an open, a leave, or the flight before a leave runs on this canvas.
    public var isInCardTransition: Bool { cardTransition != nil }

    /// `true` after the renderer drew a frame with all strokes of the load, and needs no more
    /// frames: the first frame of a canvas that opened.
    public var hasDrawnLoad: Bool {
        !renderer.needsMoreFrames && renderer.strokeCount >= content.strokes.count
    }

    /// The camera at which a card frame covers a screen of `viewSize` (D-98).
    ///
    /// - Precondition: The frame and the view have a size.
    public static func coverCamera(of frame: Rect, viewSize: Size) -> Camera {
        precondition(frame.size.width > 0 && frame.size.height > 0, "A card has a size")
        let zoom = max(viewSize.width / frame.size.width, viewSize.height / frame.size.height)
        return Camera(center: frame.center, zoom: zoom)
    }

    /// Sets the weight of the parent from the progress of the flight, and ends the transition
    /// with the flight. It runs in the frame callback and allocates nothing (PERF-01).
    func stepCardTransition() {
        guard let transition = cardTransition else { return }
        guard let progress = cameraController.flightProgress else {
            cardTransition = nil
            switch transition.kind {
            case .open: renderer.setParentWeight(0)
            case .leave:
                renderer.endTransition()
                canvasView.isUserInteractionEnabled = true
            case .settle: break
            }
            transition.onEnd()
            return
        }
        switch transition.kind {
        case .open: renderer.setParentWeight(1 - progress)
        case .leave: renderer.setParentWeight(progress)
        case .settle: break
        }
    }

    /// Prepares the leave of this canvas into its card (D-109): input goes off, and the camera
    /// flies to the camera of the open, so that the child shows what the preview shows. `onEnd`
    /// runs at the end of the flight, at once if the camera is there already.
    public func prepareLeave(onEnd: @escaping @MainActor () -> Void) {
        guard cardTransition == nil else { return }
        endTextEdit()
        canvasView.isUserInteractionEnabled = false
        let target = content.openCamera
        guard target != camera else {
            onEnd()
            return
        }
        cardTransition = CardTransition(kind: .settle, start: camera, onEnd: onEnd)
        cameraController.fly(to: target)
        canvasView.inkView.requestFrame()
    }

    /// Shows only the card that the child of a leave covers: the parent at weight 0 under the
    /// card, input off (D-108). The canvas opens at the cover camera of the card. `runLeave`
    /// then plays the leave.
    public func holdLeave(into card: Card) {
        canvasView.isUserInteractionEnabled = false
        renderer.beginLeave(into: card.id)
        renderer.setParentWeight(0)
    }

    /// Plays the leave: the camera flies from the card to the camera of CARD-04, the standard
    /// zoom centered on the card, while the parent fades in (D-98, D-99). `onEnd` runs at the
    /// end, when the transition is over and input is on again.
    public func runLeave(into card: Card, onEnd: @escaping @MainActor () -> Void) {
        guard cardTransition == nil else { return }
        cardTransition = CardTransition(kind: .leave, start: camera, onEnd: onEnd)
        cameraController.fly(to: Camera(center: card.frame.center, zoom: Limits.standardZoom))
        canvasView.inkView.requestFrame()
    }
}
