import Geometry
import Model

/// The card previews of the engine: the requests of the frames go to one loader, and its results
/// come back through the inbox (D-97).
extension RenderEngine {
    /// `true` while a preview request waits, decodes, or waits for its upload.
    var isLoadingPreviews: Bool {
        let isDecoding = previewLoader.withLock { $0?.isLoading ?? false }
        let isWaiting = inbox.withLock { !$0.decodedPreviews.isEmpty }
        let isUploading = core.withLock { !($0.previews?.pending.isEmpty ?? true) }
        assert(previewSource != nil || !isDecoding, "Only a source decodes")
        return isDecoding || isWaiting || isUploading
    }

    /// Gives the new preview requests of the last frame to the loader. A frame without requests
    /// does nothing more than one lock (PERF-01).
    func requestPreviews() {
        guard let source = previewSource else { return }
        assert(previewRequestLimit > 0, "A request limit is positive")
        core.withLock { renderer in
            renderer.takeWantedPreviews { requests, area in
                loader(for: source).request(requests, area: area)
            }
        }
    }

    /// Ends the preview render that waits or runs with `nil`, because the render thread stops
    /// before the render ends (D-131). The completions run after the locks.
    func endPreviewRender() {
        let waiting = inbox.withLock { $0.takePreviewRender() }
        let running = core.withLock { $0.previewRenderer?.takeJob() }
        waiting?.completion(nil)
        running?.request.completion(nil)
    }

    /// Returns the loader, made at the first request.
    private func loader(for source: any PreviewSource) -> PreviewLoader {
        assert(previewRequestLimit > 0, "A request limit is positive")
        return previewLoader.withLock { current in
            if let current { return current }
            // Made here only, so a frame with a loader makes no closure (PERF-01).
            let deliver: @Sendable (DecodedPreview) -> Void = { [weak self] preview in
                self?.post { $0.decodedPreviews.append(preview) }
            }
            let made = PreviewLoader(source: source, limit: previewRequestLimit, deliver: deliver)
            current = made
            return made
        }
    }
}
