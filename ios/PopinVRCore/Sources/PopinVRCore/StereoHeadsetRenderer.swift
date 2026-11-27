import Foundation
import Metal
import MetalKit
import simd

/// Minimal stereoscopic world renderer for validating ARKit 6DoF in a phone headset.
/// Draws a world-locked reference grid into left/right eye viewports.
public final class PopinVRStereoHeadsetRenderer: NSObject, MTKViewDelegate {
    public let headTracker: PopinVRHeadTracker
    public var stereoRig: PopinVRStereoRig

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let gridBuffer: MTLBuffer
    private let gridVertexCount: Int

    public init?(view: MTKView, headTracker: PopinVRHeadTracker, stereoRig: PopinVRStereoRig = .init()) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertex = library.makeFunction(name: "popinvr_grid_vertex"),
              let fragment = library.makeFunction(name: "popinvr_grid_fragment") else {
            return nil
        }

        view.colorPixelFormat = .bgra8Unorm
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        let vertices = Self.makeGridVertices()
        guard let buffer = vertices.withUnsafeBytes({ raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
        }) else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.pipeline = pipeline
        self.gridBuffer = buffer
        self.gridVertexCount = vertices.count
        self.headTracker = headTracker
        self.stereoRig = stereoRig
        super.init()

        view.device = device
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.delegate = self
    }

    public func draw(in view: MTKView) {
        guard let pose = headTracker.latestPose(),
              pose.quality != .unavailable,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }

        let width = drawable.texture.width
        let height = drawable.texture.height
        let halfWidth = width / 2
        let aspect = Float(halfWidth) / Float(max(height, 1))
        let eyeViews = stereoRig.views(worldFromCamera: pose.worldFromCamera, eyeAspectRatio: aspect)

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(gridBuffer, offset: 0, index: 0)

        for eyeView in eyeViews {
            let x = eyeView.eye == .left ? 0 : halfWidth
            let eyeWidth = eyeView.eye == .left ? halfWidth : width - halfWidth
            encoder.setViewport(MTLViewport(
                originX: Double(x), originY: 0,
                width: Double(eyeWidth), height: Double(height),
                znear: 0, zfar: 1
            ))
            var viewProjection = eyeView.projectionMatrix * eyeView.viewMatrix
            encoder.setVertexBytes(
                &viewProjection,
                length: MemoryLayout<simd_float4x4>.stride,
                index: 1
            )
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridVertexCount)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private static func makeGridVertices() -> [SIMD3<Float>] {
        var vertices: [SIMD3<Float>] = []
        let extent: Float = 10
        let step: Float = 0.5
        let count = Int(extent / step)
        for i in -count...count {
            let p = Float(i) * step
            vertices.append(SIMD3<Float>(p, -1.2, -extent))
            vertices.append(SIMD3<Float>(p, -1.2, extent))
            vertices.append(SIMD3<Float>(-extent, -1.2, p))
            vertices.append(SIMD3<Float>(extent, -1.2, p))
        }
        return vertices
    }
}
