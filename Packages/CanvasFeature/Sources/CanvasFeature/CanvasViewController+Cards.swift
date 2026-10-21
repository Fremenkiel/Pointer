/// The cards of the canvas screen (architecture.md 5.5 and 6).
extension CanvasViewController {
    /// Gives the loaded strokes and cards to the renderer. The renderer lays out the card titles
    /// off the render thread, so the first frame does not wait for them (D-92).
    func loadRenderer() {
        renderer.load(Array(content.strokes.values))
        renderer.load(Array(content.cards.values))
    }
}
