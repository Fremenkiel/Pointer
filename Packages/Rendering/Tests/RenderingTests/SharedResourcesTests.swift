import Metal
import Testing

@testable import Rendering

/// The pipelines that all renderers share (m10-plan.md task 3.3).
@Suite("Shared ink resources")
struct SharedResourcesTests {
    @Test("Two sets share their pipelines and keep a command queue each")
    func sharePipelines() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let first = try InkResources.shared(device: device)
        let second = try InkResources.shared(device: device)
        #expect(first.inkPipeline === second.inkPipeline)
        #expect(first.glyphPipeline === second.glyphPipeline)
        #expect(first.pinchPipeline === second.pinchPipeline)
        #expect(first.placeholder === second.placeholder)
        #expect(first.queue !== second.queue, "Each renderer keeps its own GPU order")
    }
}
