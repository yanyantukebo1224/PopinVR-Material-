import Foundation
import simd

/// Physical phone-and-viewer calibration. Defaults are a starting point for a Cardboard-v2-style
/// viewer, not a universal optical calibration; tune them for the actual printed lenses.
public struct PopinVRLensProfile: Sendable {
    public var screenWidthMeters: Float
    public var screenHeightMeters: Float
    public var screenToLensDistance: Float
    public var interpupillaryDistance: Float
    public var distortionK1: Float
    public var distortionK2: Float
    public var maximumEyeFOVRadians: Float

    public init(
        screenWidthMeters: Float,
        screenHeightMeters: Float,
        screenToLensDistance: Float,
        interpupillaryDistance: Float,
        distortionK1: Float,
        distortionK2: Float,
        maximumEyeFOVDegrees: Float = 60
    ) {
        self.screenWidthMeters = screenWidthMeters
        self.screenHeightMeters = screenHeightMeters
        self.screenToLensDistance = screenToLensDistance
        self.interpupillaryDistance = interpupillaryDistance
        self.distortionK1 = distortionK1
        self.distortionK2 = distortionK2
        self.maximumEyeFOVRadians = maximumEyeFOVDegrees * .pi / 180
    }

    /// Approximate landscape active-area dimensions of iPhone 16e. Adjust after measuring the
    /// physical panel and viewer tray; the lens coefficients are Cardboard-v2 starting values.
    public static let cardboardV2IPhone16e = PopinVRLensProfile(
        screenWidthMeters: 0.1467,
        screenHeightMeters: 0.0676,
        screenToLensDistance: 0.0393,
        interpupillaryDistance: 0.064,
        distortionK1: 0.3358,
        distortionK2: 0.5535
    )

    public func eyeOffsetX(_ eye: PopinVREye) -> Float {
        (eye == .left ? -0.5 : 0.5) * interpupillaryDistance
    }

    /// FOV extents from the eye's optical axis, in radians: left, right, bottom, top.
    public func fieldOfView(_ eye: PopinVREye) -> SIMD4<Float> {
        let halfScreen = screenWidthMeters * 0.5
        let centerX = eye == .left
            ? (screenWidthMeters - interpupillaryDistance) * 0.5
            : (screenWidthMeters + interpupillaryDistance) * 0.5 - halfScreen
        let halfHeight = screenHeightMeters * 0.5
        let left = abs(distort(SIMD2(-centerX / screenToLensDistance, 0)).x)
        let right = abs(distort(SIMD2((halfScreen - centerX) / screenToLensDistance, 0)).x)
        let vertical = abs(distort(SIMD2(0, halfHeight / screenToLensDistance)).y)
        let cap = tan(maximumEyeFOVRadians)
        return SIMD4(
            atan(min(left, cap)),
            atan(min(right, cap)),
            atan(min(vertical, cap)),
            atan(min(vertical, cap))
        )
    }

    public func projectionMatrix(
        _ eye: PopinVREye,
        near: Float,
        far: Float
    ) -> simd_float4x4 {
        let fov = fieldOfView(eye)
        let n = max(near, 0.001)
        let f = max(far, n + 0.01)
        let l = -tan(fov.x) * n
        let r = tan(fov.y) * n
        let b = -tan(fov.z) * n
        let t = tan(fov.w) * n
        return simd_float4x4(columns: (
            SIMD4<Float>(2 * n / (r - l), 0, 0, 0),
            SIMD4<Float>(0, 2 * n / (t - b), 0, 0),
            SIMD4<Float>((r + l) / (r - l), (t + b) / (t - b), f / (n - f), -1),
            SIMD4<Float>(0, 0, n * f / (n - f), 0)
        ))
    }

    /// Cardboard polynomial radial distortion in tangent-angle coordinates.
    public func distort(_ point: SIMD2<Float>) -> SIMD2<Float> {
        let radiusSquared = simd_length_squared(point)
        let factor = 1 + distortionK1 * radiusSquared
            + distortionK2 * radiusSquared * radiusSquared
        return point * factor
    }

    /// Maps a screen point within one eye's half-screen to the eye-texture UV.
    /// This is the mapping for the post-render lens-warp pass; it is not applied by the grid preview yet.
    public func screenUVToTextureUV(_ uv: SIMD2<Float>, eye: PopinVREye) -> SIMD2<Float> {
        let halfScreen = screenWidthMeters * 0.5
        let centerX = eye == .left
            ? (screenWidthMeters - interpupillaryDistance) * 0.5
            : (screenWidthMeters + interpupillaryDistance) * 0.5 - halfScreen
        let screenX = uv.x * halfScreen
        let screenY = (1 - uv.y) * screenHeightMeters
        let tanAngle = SIMD2(
            (screenX - centerX) / screenToLensDistance,
            (screenY - screenHeightMeters * 0.5) / screenToLensDistance
        )
        let warped = distort(tanAngle)
        let fov = fieldOfView(eye)
        let left = -tan(fov.x)
        let right = tan(fov.y)
        let bottom = -tan(fov.z)
        let top = tan(fov.w)
        let textureX = (warped.x - left) / max(right - left, 1e-5)
        let textureY = 1 - (warped.y - bottom) / max(top - bottom, 1e-5)
        return SIMD2(textureX, textureY)
    }
}
