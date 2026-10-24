import Geometry
import Model
import Synchronization
import os

/// Reads and decodes the card previews off the main actor and off the render thread (D-97,
/// m6-plan.md section 4, rule 5).
///
/// One long-lived task serves all requests of a renderer, one at a time, so the decode runs on
/// one serial path and makes no task per frame. A request whose card left the texture area is
/// dropped before its decode.
final class PreviewLoader: Sendable {
    /// The state that the render thread and the task share.
    private struct State {
        var queue: [PreviewRequest] = []
        /// The texture area of the newest request, in canvas space.
        var area: Rect?
        /// The requests that the task took and did not deliver yet.
        var inFlight = 0
    }

    /// The lock of the state, which the loader and its task share.
    private final class Shared: Sendable {
        let state: Mutex<State>

        init(limit: Int) {
            var initial = State()
            initial.queue.reserveCapacity(limit)
            state = Mutex(initial)
        }
    }

    private let shared: Shared
    private let signal: AsyncStream<Void>.Continuation
    private let task: Task<Void, Never>
    private let limit: Int

    /// Makes the loader and starts its task.
    ///
    /// - Precondition: `limit` is positive.
    init(
        source: any PreviewSource,
        limit: Int,
        deliver: @escaping @Sendable (DecodedPreview) -> Void
    ) {
        precondition(limit > 0, "A request limit is positive, got \(limit)")
        let shared = Shared(limit: limit)
        let (stream, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.shared = shared
        self.signal = signal
        self.limit = limit
        task = Task.detached(priority: .userInitiated) {
            await Self.run(stream, shared: shared, source: source, limit: limit, deliver: deliver)
        }
    }

    deinit {
        // The waiting requests go, so a loader of a canvas that went loads no more child canvas.
        shared.state.withLock { $0.queue.removeAll() }
        signal.finish()
        task.cancel()
    }

    /// `true` while a request waits or its decode runs.
    var isLoading: Bool { shared.state.withLock { !$0.queue.isEmpty || $0.inFlight > 0 } }

    /// Adds the requests of a frame. A request beyond `limit` waiting requests is dropped, and
    /// the atlas asks for it again in a later frame.
    func request(_ requests: [PreviewRequest], area: Rect) {
        precondition(requests.count <= Limits.maxNodesPerCanvas, "Too many preview requests")
        guard !requests.isEmpty else { return }
        shared.state.withLock { current in
            current.area = area
            for request in requests where current.queue.count < limit {
                current.queue.append(request)
            }
            assert(current.queue.count <= limit, "At most \(limit) requests wait")
        }
        signal.yield()
    }

    /// Serves the requests until the loader goes.
    private static func run(
        _ stream: AsyncStream<Void>,
        shared: Shared,
        source: any PreviewSource,
        limit: Int,
        deliver: @Sendable (DecodedPreview) -> Void
    ) async {
        precondition(limit > 0, "A request limit is positive, got \(limit)")
        let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Rendering")
        let signposter = OSSignposter(subsystem: "dk.saarikivi.pointer", category: "Rendering")
        var decoder = PreviewDecoder()
        for await _ in stream {
            do {
                try Task.checkCancellation()
            } catch {
                return
            }
            // A signal can stand for several requests, and the limit bounds them (FLOW-03).
            for _ in 0..<limit {
                // A cancel ends the loop before the next request: each one can load a whole
                // child canvas (review after M9).
                guard !Task.isCancelled, let (request, area) = take(from: shared) else { break }
                let interval = signposter.beginInterval("PreviewDecode")
                let result = await load(request, area: area, source: source, decoder: &decoder)
                signposter.endInterval("PreviewDecode", interval)
                if case .unavailable = result.outcome {
                    logger.info("No valid preview of card \(request.card.rawValue)")
                }
                deliver(result)
                shared.state.withLock { $0.inFlight -= 1 }
            }
        }
    }

    /// Takes the oldest request and the newest texture area.
    private static func take(from shared: Shared) -> (PreviewRequest, Rect?)? {
        // The caller holds no lock, so this lock is not taken twice.
        shared.state.withLock { current -> (PreviewRequest, Rect?)? in
            guard !current.queue.isEmpty else { return nil }
            current.inFlight += 1
            assert(current.inFlight > 0, "A taken request is in flight")
            return (current.queue.removeFirst(), current.area)
        }
    }

    /// Reads and decodes one preview, or drops the request of a card outside `area`.
    private static func load(
        _ request: PreviewRequest,
        area: Rect?,
        source: any PreviewSource,
        decoder: inout PreviewDecoder
    ) async -> DecodedPreview {
        func result(
            _ outcome: DecodedPreview.Outcome,
            width: Int = 0,
            height: Int = 0
        ) -> DecodedPreview {
            precondition(width >= 0 && height >= 0, "A preview has no negative size")
            return DecodedPreview(
                card: request.card,
                step: request.step,
                width: width,
                height: height,
                outcome: outcome
            )
        }
        precondition(request.step <= PreviewDecoder.maxSide, "Step \(request.step) is too large")
        if let area, !area.intersects(request.bounds) {
            return result(.dropped)
        }
        let canvas = CanvasID(request.card)
        guard let data = await source.preview(of: canvas, cardAspect: request.cardAspect),
            let image = decoder.decode(data, step: request.step)
        else { return result(.unavailable) }
        return result(.pixels(image.pixels), width: image.width, height: image.height)
    }
}
