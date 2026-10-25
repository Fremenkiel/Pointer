import Geometry
import Model

/// The card previews of the engine: the requests of the frames go to one loader, and its results
/// come back through the inbox (D-97).
extension RenderEngine {
    /// `true` while a preview request waits, decodes, or waits for its upload.
    var isLoadingPreviews: Bool { inbox.withLock { $0.isLoadingPreviews } }

    /// Gives the new preview requests of the last frame to the loader. A frame without requests
    /// does nothing more than one lock (PERF-01).
    func requestPreviews() {
        guard let source = previewSource else { return }
        assert(previewRequestLimit > 0, "A request limit is positive")
        core.withLock { renderer in
            renderer.takeWantedPreviews { requests, area in
                send(requests, area: area, to: source)
            }
        }
    }

    /// Counts the requests as out and gives them to the loader. The count goes up before the
    /// loader gets the requests, so the loading state has no gap. The loader drops the requests
    /// past its limit, and they no longer count.
    private func send(_ requests: [PreviewRequest], area: Rect, to source: any PreviewSource) {
        inbox.withLock { box in
            box.previewRequestsOut += requests.count
            box.hasPreviewsToRequest = false
        }
        let dropped = requests.count - loader(for: source).request(requests, area: area)
        assert(dropped >= 0, "The loader takes at most the requests that it gets")
        if dropped > 0 { inbox.withLock { $0.previewRequestsOut -= dropped } }
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
                self?.post { box in
                    box.decodedPreviews.append(preview)
                    box.previewRequestsOut -= 1
                    assert(box.previewRequestsOut >= 0, "A request is delivered once")
                }
            }
            let made = PreviewLoader(source: source, limit: previewRequestLimit, deliver: deliver)
            current = made
            return made
        }
    }
}
