import Metal
import QuartzCore

/// One capsule in canvas points. 20 bytes, matches `Capsule` in Shaders.metal.
struct Capsule {
    var startX: Float
    var startY: Float
    var endX: Float
    var endY: Float
    var radius: Float

    init(_ a: CGPoint, _ b: CGPoint, radius: Double) {
        startX = Float(a.x)
        startY = Float(a.y)
        endX = Float(b.x)
        endY = Float(b.y)
        self.radius = Float(radius)
    }
}

private struct Uniforms {
    var viewWidth: Float
    var viewHeight: Float
    var zoom: Float
    var pixelSize: Float
}

/// Draws capsules as instanced quads. Spike code: one shared buffer for all finished capsules.
final class CapsuleRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let committed: MTLBuffer
    private(set) var committedCount = 0
    private let capacity = 1 << 20

    init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        let library = device.makeDefaultLibrary()!
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "capsuleVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "capsuleFragment")
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try! device.makeRenderPipelineState(descriptor: descriptor)
        committed = device.makeBuffer(length: capacity * MemoryLayout<Capsule>.stride, options: .storageModeShared)!
    }

    /// Appends finished capsules. The GPU reads only the range below `committedCount` of earlier frames.
    func append(_ capsules: [Capsule]) {
        let room = min(capsules.count, capacity - committedCount)
        guard room > 0 else { return }
        let target = committed.contents().bindMemory(to: Capsule.self, capacity: capacity)
        capsules.withUnsafeBufferPointer { source in
            (target + committedCount).update(from: source.baseAddress!, count: room)
        }
        committedCount += room
    }

    func clear() {
        committedCount = 0
    }

    /// Encodes one frame into `texture`: all committed capsules and the temporary `tail`.
    func encode(
        into commandBuffer: MTLCommandBuffer,
        texture: MTLTexture,
        tail: [Capsule],
        committedRange: Range<Int>? = nil,
        zoom: Double,
        viewSize: CGSize,
        scale: Double
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = Uniforms(
            viewWidth: Float(viewSize.width),
            viewHeight: Float(viewSize.height),
            zoom: Float(zoom),
            pixelSize: Float(1 / (zoom * scale)))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        let range = committedRange ?? 0..<committedCount
        if !range.isEmpty {
            encoder.setVertexBuffer(committed, offset: range.lowerBound * MemoryLayout<Capsule>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: range.count)
        }
        if !tail.isEmpty {
            tail.withUnsafeBytes { bytes in
                if bytes.count <= 4096 {
                    encoder.setVertexBytes(bytes.baseAddress!, length: bytes.count, index: 0)
                } else if let buffer = device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count) {
                    encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                }
            }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: tail.count)
        }
        encoder.endEncoding()
    }

    /// Draws a range of committed capsules into a new CPU-readable texture. Used for the handoff
    /// comparison of the hybrid spike.
    func renderOffscreen(
        range: Range<Int>, zoom: Double, viewSize: CGSize, scale: Double,
        completion: @escaping (MTLTexture) -> Void
    ) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(viewSize.width * scale),
            height: Int(viewSize.height * scale),
            mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor),
            let commandBuffer = queue.makeCommandBuffer()
        else { return }
        encode(
            into: commandBuffer, texture: texture, tail: [], committedRange: range,
            zoom: zoom, viewSize: viewSize, scale: scale)
        commandBuffer.addCompletedHandler { _ in
            DispatchQueue.main.async { completion(texture) }
        }
        commandBuffer.commit()
    }
}
