import Foundation
import simd

public enum PopinVREye: Sendable {
    case left
    case right

    fileprivate var sign: Float { self == .left ? -1 : 1 }
}

public struct PopinVREyeView: Sendable {
    public let eye: PopinVREye
    public let worldFromEye: simd_float4x4
    public let viewMatrix: simd_float4x4
    public let projectionMatrix: simd_float4x4
}

/// Parallel-axis, off-axis stereo camera rig.
/// ARKit supplies the 6DoF device pose; this rig creates two virtual eye poses
/// separated by IPD. It does not claim to access the iPhone's physical display optics.
public struct PopinVRStereoRig: Sendable {
    public var interpupillaryDistance: Float
    public var verticalFieldOfViewRadians: Float
    public var convergenceDistance: Float
    public var nearPlane: Float
    public var farPlane: Float

    public init(
        interpupillaryDistance: Float = 0.064,
        verticalFieldOfViewRadians: Float = .pi / 2,
        convergenceDistance: Float = 2.0,
        nearPlane: Float = 0.03,
        farPlane: Float = 100.0
    ) {
        self.interpupillaryDistance = interpupillaryDistance
        self.verticalFieldOfViewRadians = verticalFieldOfViewRadians
        self.convergenceDistance = convergenceDistance
        self.nearPlane = nearPlane
        self.farPlane = farPlane
    }

    public func views(worldFromCamera: simd_float4x4, eyeAspectRatio: Float) -> [PopinVREyeView] {
        [makeView(.left, worldFromCamera: worldFromCamera, aspect: eyeAspectRatio),
         makeView(.right, worldFromCamera: worldFromCamera, aspect: eyeAspectRatio)]
    }

    private func makeView(_ eye: PopinVREye, worldFromCamera: simd_float4x4, aspect: Float) -> PopinVREyeView {
        let halfIPD = interpupillaryDistance * 0.5
        let localOffset = SIMD3<Float>(eye.sign * halfIPD, 0, 0)
        let translation = simd_float4x4(translation: localOffset)
        let worldFromEye = worldFromCamera * translation
        let view = simd_inverse(worldFromEye)
        let projection = makeProjection(aspect: max(aspect, 0.01), eyeSign: eye.sign)
        return PopinVREyeView(eye: eye, worldFromEye: worldFromEye, viewMatrix: view, projectionMatrix: projection)
    }

    private func makeProjection(aspect: Float, eyeSign: Float) -> simd_float4x4 {
        let near = max(nearPlane, 0.001)
        let far = max(farPlane, near + 0.01)
        let tanHalfVertical = tan(verticalFieldOfViewRadians * 0.5)
        let yScale = 1 / tanHalfVertical
        let xScale = yScale / aspect
        // Off-axis shift makes the two parallel cameras converge at convergenceDistance.
        let horizontalShift = -eyeSign * xScale * (interpupillaryDistance * 0.5) / max(convergenceDistance, 0.05)

        return simd_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(horizontalShift, 0, far / (near - far), -1),
            SIMD4<Float>(0, 0, (near * far) / (near - far), 0)
        ))
    }
}

private extension simd_float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1)
    }
}
