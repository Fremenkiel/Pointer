import Geometry
import Metal
import Model

/// The card previews of the frame work (architecture.md 5.5, D-97).
extension FrameRenderer {
    /// The canvas area of the texture that the green passes draw now: the build target, or the
    /// front texture.
    var previewArea: Rect? { (layer?.build?.target ?? layer?.front)?.canvasRect }

    /// Makes the preview atlas at the first card, once per renderer (m6-plan.md section 4,
    /// rule 2). A failure leaves the cards without previews and logs it.
    func makePreviewAtlasIfNeeded() {
        guard previews == nil, cards.count > 0 else { return }
        precondition(configuration.previewRequestLimit > 0, "A request limit is positive")
        do {
            let atlas = try PreviewAtlas(
                resources: resources,
                byteBudget: configuration.previewAtlasByteBudget,
                requestLimit: configuration.previewRequestLimit
            )
            previews = atlas
            textEncoder.previews = atlas
        } catch {
            logger.error("The preview atlas failed: \(String(describing: error))")
        }
    }

    /// Takes the results of the loader. The next frame uploads them.
    func takePreviews(_ decoded: [DecodedPreview]) {
        guard let previews, !decoded.isEmpty else { return }
        precondition(decoded.count <= Limits.maxNodesPerCanvas, "Too many previews in a frame")
        previews.pending.append(contentsOf: decoded)
    }

    /// Copies the waiting previews into the atlas with one blit, as far as the staging buffer of
    /// the frame holds them, and redraws the green channel of their cards (D-96).
    func uploadPreviews(_ context: FrameContext) {
        guard let previews, !previews.pending.isEmpty else { return }
        precondition(context.frame > 0, "Frames count from 1")
        previews.uploads.beginFrame()
        var blit: (any MTLBlitCommandEncoder)?
        var taken = 0
        for preview in previews.pending {
            if case .pixels(let pixels) = preview.outcome {
                guard previews.uploads.used + pixels.count <= PreviewUploads.capacity else { break }
            }
            taken += 1
            let entry = previews.store(preview, frame: context.frame)
            guard let bounds = cards.entries[preview.card]?.bounds else {
                // The card left the canvas while its preview was on the way.
                previews.forget(preview.card)
                continue
            }
            guard let entry, case .pixels(let pixels) = preview.outcome,
                let offset = previews.uploads.append(pixels)
            else { continue }
            if blit == nil { blit = context.commandBuffer.makeBlitCommandEncoder() }
            blit?.copy(
                from: previews.uploads.buffer,
                sourceOffset: offset,
                sourceBytesPerRow: entry.width,
                sourceBytesPerImage: pixels.count,
                sourceSize: MTLSize(width: entry.width, height: entry.height, depth: 1),
                to: previews.texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: entry.x, y: entry.y, z: 0)
            )
            previews.dirtyArea = previews.dirtyArea.map { Self.union($0, bounds) } ?? bounds
        }
        blit?.endEncoding()
        previews.pending.removeFirst(taken)
        assert(taken > 0 || previews.pending.isEmpty, "A frame takes at least one preview")
    }

    /// Gives the new requests of the frame to the loader.
    func takeWantedPreviews(_ body: ([PreviewRequest], Rect) -> Void) {
        guard let previews, !previews.wanted.isEmpty, let area = previewArea else { return }
        precondition(previews.wanted.count <= previews.requestLimit, "Too many new requests")
        body(previews.wanted, area)
        previews.wanted.removeAll(keepingCapacity: true)
    }
}
