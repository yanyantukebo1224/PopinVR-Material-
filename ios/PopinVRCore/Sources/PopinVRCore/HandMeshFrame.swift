import Foundation
import simd

public enum PopinVRHandedness: Sendable {
    case left
    case right
    case unknown
}

/// A complete per-frame mesh payload for the stereo renderer.
/// Vertices and joints are expressed in hand-local coordinates, metres; cameraFromHand places them in the camera frame. Faces are triangle indices.
/// The source pipeline is expected to produce the 2,859-vertex SOMA-X topology.
public struct PopinVRHandMeshFrame: Sendable {
    public let timestamp: TimeInterval
    public let handedness: PopinVRHandedness
    public let confidence: Float
    public let cameraFromHand: simd_float4x4
    public let vertices: [SIMD3<Float>]
    public let triangleIndices: [UInt32]
    public let joints: [SIMD3<Float>]

    public init(
        timestamp: TimeInterval,
        handedness: PopinVRHandedness,
        confidence: Float,
        cameraFromHand: simd_float4x4,
        vertices: [SIMD3<Float>],
        triangleIndices: [UInt32],
        joints: [SIMD3<Float>]
    ) {
        self.timestamp = timestamp
        self.handedness = handedness
        self.confidence = confidence
        self.cameraFromHand = cameraFromHand
        self.vertices = vertices
        self.triangleIndices = triangleIndices
        self.joints = joints
    }

    public var isValidSOMAXMesh: Bool {
        vertices.count == 2_859 &&
        triangleIndices.count == 5_692 * 3 &&
        triangleIndices.allSatisfy { Int($0) < vertices.count }
    }
}
