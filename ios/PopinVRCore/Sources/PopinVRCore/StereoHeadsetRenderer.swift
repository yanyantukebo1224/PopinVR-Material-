import Foundation
import Metal
import MetalKit
import simd

private struct PopinVRHandUniforms {
    var modelViewProjection: simd_float4x4
    var modelToWorld: simd_float4x4
    var color: SIMD4<Float>
}

private struct PopinVRGPUHandMesh {
    let positions: MTLBuffer
    let normals: MTLBuffer
    let indices: MTLBuffer
    let indexCount: Int
    let cameraFromHand: simd_float4x4
    let color: SIMD4<Float>
}

/// Stereoscopic Metal renderer for a phone headset.
/// ARKit supplies the 6DoF camera pose; each eye gets its own off-axis view.
/// The grid is a tracking reference and submitted SOMA-X meshes are drawn as 3D triangles.
public final class PopinVRStereoHeadsetRenderer: NSObject, MTKViewDelegate {
    public let headTracker: PopinVRHeadTracker
    public var stereoRig: PopinVRStereoRig

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let gridPipeline: MTLRenderPipelineState
    private let handPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let gridBuffer: MTLBuffer
    private let gridVertexCount: Int
    private let handsLock = NSLock()
    private var gpuHands: [PopinVRGPUHandMesh] = []

    public init?(view: MTKView, headTracker: PopinVRHeadTracker, stereoRig: PopinVRStereoRig = .init()) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: .module),
              let gridVertex = library.makeFunction(name: "popinvr_grid_vertex"),
              let gridFragment = library.makeFunction(name: "popinvr_grid_fragment"),
              let handVertex = library.makeFunction(name: "popinvr_hand_vertex"),
              let handFragment = library.makeFunction(name: "popinvr_hand_fragment") else {
            return nil
        }

        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float

        let gridDescriptor = MTLRenderPipelineDescriptor()
        gridDescriptor.vertexFunction = gridVertex
        gridDescriptor.fragmentFunction = gridFragment
        gridDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        gridDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        let handDescriptor = MTLRenderPipelineDescriptor()
        handDescriptor.vertexFunction = handVertex
        handDescriptor.fragmentFunction = handFragment
        handDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        handDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        guard let gridPipeline = try? device.makeRenderPipelineState(descriptor: gridDescriptor),
              let handPipeline = try? device.makeRenderPipelineState(descriptor: handDescriptor) else {
            return nil
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            return nil
        }

        let vertices = Self.makeGridVertices()
        guard let buffer = vertices.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> MTLBuffer? in
            guard let base = raw.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        } else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.gridPipeline = gridPipeline
        self.handPipeline = handPipeline
        self.depthState = depthState
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

    /// Replace the currently displayed hand meshes. Call when a newer inference result is ready;
    /// stale inference frames should be dropped before reaching this method.
    public func updateHands(_ frames: [PopinVRHandMeshFrame]) {
        var next: [PopinVRGPUHandMesh] = []
        for frame in frames where frame.isValidSOMAXMesh {
            let normals = Self.vertexNormals(vertices: frame.vertices, indices: frame.triangleIndices)
            guard let positionBuffer = Self.makeBuffer(frame.vertices, on: device),
                  let normalBuffer = Self.makeBuffer(normals, on: device),
                  let indexBuffer = Self.makeBuffer(frame.triangleIndices, on: device) else {
                continue
            }
            let color: SIMD4<Float>
            switch frame.handedness {
            case .left: color = SIMD4<Float>(0.22, 0.78, 0.98, 1)
            case .right: color = SIMD4<Float>(0.98, 0.48, 0.25, 1)
            case .unknown: color = SIMD4<Float>(0.72, 0.78, 0.86, 1)
            }
            next.append(PopinVRGPUHandMesh(
                positions: positionBuffer,
                normals: normalBuffer,
                indices: indexBuffer,
                indexCount: frame.triangleIndices.count,
                cameraFromHand: frame.cameraFromHand,
                color: color
            ))
        }
        handsLock.lock()
        gpuHands = next
        handsLock.unlock()
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

        handsLock.lock()
        let hands = gpuHands
        handsLock.unlock()

        encoder.setDepthStencilState(depthState)
        encoder.setRenderPipelineState(gridPipeline)
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

            encoder.setRenderPipelineState(handPipeline)
            for hand in hands {
                let modelToWorld = pose.worldFromCamera * hand.cameraFromHand
                var uniforms = PopinVRHandUniforms(
                    modelViewProjection: viewProjection * modelToWorld,
                    modelToWorld: modelToWorld,
                    color: hand.color
                )
                encoder.setVertexBuffer(hand.positions, offset: 0, index: 0)
                encoder.setVertexBuffer(hand.normals, offset: 0, index: 1)
                encoder.setVertexBytes(
                    &uniforms,
                    length: MemoryLayout<PopinVRHandUniforms>.stride,
                    index: 2
                )
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: hand.indexCount,
                    indexType: .uint32,
                    indexBuffer: hand.indices,
                    indexBufferOffset: 0
                )
            }
            encoder.setRenderPipelineState(gridPipeline)
            encoder.setVertexBuffer(gridBuffer, offset: 0, index: 0)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private static func makeBuffer<T>(_ values: [T], on device: MTLDevice) -> MTLBuffer? {
        values.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return nil }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
    }

    private static func vertexNormals(vertices: [SIMD3<Float>], indices: [UInt32]) -> [SIMD3<Float>] {
        var normals = Array(repeating: SIMD3<Float>.zero, count: vertices.count)
        guard indices.count.isMultiple(of: 3) else { return normals }
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            guard a < vertices.count, b < vertices.count, c < vertices.count else { continue }
            let normal = simd_cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
            normals[a] += normal
            normals[b] += normal
            normals[c] += normal
        }
        return normals.map { simd_length_squared($0) > 1e-10 ? simd_normalize($0) : SIMD3<Float>(0, 0, 1) }
    }

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
