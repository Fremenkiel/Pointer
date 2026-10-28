import Foundation
import Geometry
import Model
import Synchronization
import Testing

@testable import Rendering

/// A request past the limit of the loader (review of 2026-10-28, 3.2.10).
@Suite("Preview loader past its limit")
struct PreviewLoaderDropTests {
    private static func request(_ index: UInt8) -> PreviewRequest {
        PreviewRequest(
            card: CardID(
                rawValue: UUID(uuid: (9, index, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            ),
            bounds: Rect(origin: .zero, size: Size(width: 100, height: 70)),
            step: 128,
            cardAspect: 1
        )
    }

    @Test("A request past the limit comes back dropped, so the atlas asks again later")
    func droppedRequestComesBack() async throws {
        let source = GatedPreviews()
        let delivered = Mutex<[DecodedPreview]>([])
        let loader = PreviewLoader(source: source, limit: 1) { preview in
            delivered.withLock { $0.append(preview) }
        }
        let first = Self.request(1)
        let second = Self.request(2)
        loader.request(
            [first, second],
            area: Rect(origin: .zero, size: Size(width: 1, height: 1))
        )
        var results: [DecodedPreview] = []
        for _ in 0..<500 where results.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
            results = delivered.withLock { $0 }
        }
        #expect(results.map(\.card) == [second.card], "The first request waits at the gate")
        if case .dropped = results.first?.outcome {
        } else {
            Issue.record("The second request did not come back as dropped: \(results)")
        }
        source.open.yield()
        for _ in 0..<500 where delivered.withLock({ $0.count }) < 2 {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(delivered.withLock { $0.count } == 2)
    }
}
