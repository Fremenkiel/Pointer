import Dispatch
import Geometry
import Metal
import QuartzCore

/// The render of the preview of the shown canvas at a leave (the M6 plan task 3.4, D-97).
extension FrameRenderer {
    /// Starts the render of a preview. The targets come at the first request. A failure ends the
    /// request with `nil` and a log entry.
    func startPreviewRender(_ request: PreviewRenderRequest) {
        precondition(request.cardAspect > 0, "Card aspect \(request.cardAspect)")
        if previewRenderer == nil {
            do {
                previewRenderer = try PreviewRenderer(resources: resources)
            } catch {
                logger.error("The preview targets failed: \(String(describing: error))")
                request.endWithoutImage()
                return
            }
        }
        guard let renderer = previewRenderer else { return }
        renderer.start(request, viewSize: viewSize)
        guard let job = renderer.job else { return }
        renderer.slots.removeAll(keepingCapacity: true)
        renderer.greens.removeAll(keepingCapacity: true)
        store.grid.forEachItem(touching: job.region) { renderer.slots.append($0) }
        cards.grid.forEachItem(touching: job.region) { renderer.greens.append(.card($0)) }
        texts.grid.forEachItem(touching: job.region) { renderer.greens.append(.textBox($0)) }
        assert(renderer.slots.count <= store.count, "The job lists each stroke once")
    }

    /// Draws the next chunk of the preview on a frame that changes nothing on the screen. The
    /// frame takes no drawable: the shown frame stays, and the present of an unchanged frame
    /// after an idle of the display made a late interval (the M10 plan section 6.44). The chunk
    /// gets the budget of such a frame, `previewChunkTimeBudget`.
    ///
    /// - Precondition: A preview render is in progress.
    /// - Returns: `true` if the renderer needs another frame.
    func renderPreviewChunk() -> Bool {
        precondition(hasPreviewChunk, "A preview chunk needs a preview render in progress")
        guard let commandBuffer = resources.queue.makeCommandBuffer() else { return false }
        frame += 1
        let context = FrameContext(commandBuffer: commandBuffer, frame: frame)
        encoder.beginFrame(context)
        textEncoder.beginFrame(buildBudget: configuration.previewChunkTimeBudget)
        continuePreviewRender(context, budget: configuration.previewChunkTimeBudget)
        commandBuffer.commit()
        return needsMoreFrames
    }

    /// Draws the next chunk of the preview in progress, on a frame without a running build: the
    /// ink inside the instance budget, then the cards and the text, then the resolve. The chunk
    /// ends at `budget` seconds of render-thread time.
    func continuePreviewRender(_ context: FrameContext, budget: Double) {
        guard let renderer = previewRenderer, var job = renderer.job, layer?.build == nil else {
            return
        }
        assert(job.greenCursor <= renderer.greens.count, "A preview job is past its text and cards")
        RenderSignpost.begin("PreviewRender")
        defer { RenderSignpost.end("PreviewRender") }
        let deadline = CACurrentMediaTime() + budget
        if !job.hasCleared || job.inkCursor < renderer.slots.count {
            let options = InkPassOptions(
                clear: !job.hasCleared,
                instanceBudget: configuration.instanceBudgetPerFrame,
                deadline: deadline
            )
            job.inkCursor = encoder.encodePass(
                context,
                target: job.target,
                slots: renderer.slots,
                cursor: job.inkCursor,
                options: options
            )
            job.hasCleared = true
            renderer.job = job
            return
        }
        if job.greenCursor < renderer.greens.count {
            var options = TextEncoder.Options()
            options.deadline = deadline
            options.drawsPreviews = false
            job.greenCursor = textEncoder.encodePass(
                context,
                target: job.target,
                ids: renderer.greens,
                cursor: job.greenCursor,
                options: options
            )
            renderer.job = job
            return
        }
        finishPreview(job, renderer: renderer, commandBuffer: context.commandBuffer)
        renderer.job = nil
    }

    /// Resolves the two channels into one, copies the image into the readback buffer, and gives
    /// it to the completion off the main actor when the GPU completes.
    private func finishPreview(
        _ job: PreviewRenderer.Job,
        renderer: PreviewRenderer,
        commandBuffer: any MTLCommandBuffer
    ) {
        precondition(job.image.size.width <= PreviewRenderer.side, "The image fits the target")
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = renderer.resolved
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        let width = job.image.size.width
        let height = job.image.size.height
        // A buffer of its own for each preview, so that no later preview writes it during the read.
        guard
            let readback = renderer.resources.device.makeBuffer(
                length: width * height,
                options: .storageModeShared
            ),
            let resolve = commandBuffer.makeRenderCommandEncoder(descriptor: pass),
            let blit = Self.resolve(resolve, renderer: renderer, commandBuffer: commandBuffer)
        else {
            job.request.endWithoutImage()
            return
        }
        blit.copy(
            from: renderer.resolved,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: job.image.origin,
            sourceSize: job.image.size,
            to: readback,
            destinationOffset: 0,
            destinationBytesPerRow: width,
            destinationBytesPerImage: width * height
        )
        blit.endEncoding()
        PreviewRenderer.readOnCompletion(
            of: commandBuffer,
            from: readback,
            width: width,
            height: height,
            completion: job.request.completion
        )
    }

    /// Encodes the resolve pass into `encoder` and returns a blit encoder after it.
    ///
    /// - Returns: The blit encoder, or `nil` if Metal gives none.
    static func resolve(
        _ encoder: any MTLRenderCommandEncoder,
        renderer: PreviewRenderer,
        commandBuffer: any MTLCommandBuffer
    ) -> (any MTLBlitCommandEncoder)? {
        assert(renderer.resolved.pixelFormat == InkResources.maskFormat, "One channel")
        encoder.setRenderPipelineState(renderer.resources.previewResolvePipeline)
        encoder.setFragmentTexture(renderer.coverage, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return commandBuffer.makeBlitCommandEncoder()
    }
}
