import Foundation
import simd

public enum PopinVRWindowKind: String, Codable, Sendable {
    case home
    case settings
    case performance
    case browser
    case video
}

public struct PopinVRSpatialWindow: Identifiable, Sendable {
    public let id: UUID
    public var kind: PopinVRWindowKind
    public var title: String
    public var worldFromWindow: simd_float4x4
    public var sizeMeters: SIMD2<Float>
    public var isVisible: Bool
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        kind: PopinVRWindowKind,
        title: String,
        worldFromWindow: simd_float4x4,
        sizeMeters: SIMD2<Float> = SIMD2<Float>(0.9, 0.58),
        isVisible: Bool = true,
        isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.worldFromWindow = worldFromWindow
        self.sizeMeters = sizeMeters
        self.isVisible = isVisible
        self.isPinned = isPinned
    }
}

/// Scene-level window manager. UI panels are world-anchored, not attached to the
/// iPhone's 2D app chrome. Renderer and input system consume this shared state.
@MainActor
public final class PopinVRSpatialWorkspace {
    public private(set) var windows: [PopinVRSpatialWindow] = []
    public var onChange: (() -> Void)?

    public init() {}

    public func installDefaultWorkspace(worldFromHead: simd_float4x4) {
        guard windows.isEmpty else { return }
        windows = [
            makeWindow(.home, title: "PopinVR", head: worldFromHead, offset: SIMD3<Float>(0, 0, -1.15), size: SIMD2<Float>(1.0, 0.68)),
            makeWindow(.settings, title: "Settings", head: worldFromHead, offset: SIMD3<Float>(0.92, -0.12, -1.35), size: SIMD2<Float>(0.62, 0.72), visible: false),
            makeWindow(.performance, title: "System", head: worldFromHead, offset: SIMD3<Float>(-0.92, -0.12, -1.35), size: SIMD2<Float>(0.54, 0.46), visible: false),
            makeWindow(.browser, title: "Browser", head: worldFromHead, offset: SIMD3<Float>(0, 0.02, -1.55), size: SIMD2<Float>(1.2, 0.76), visible: false)
        ]
        onChange?()
    }

    public func show(_ kind: PopinVRWindowKind) {
        update(kind) { $0.isVisible = true }
    }

    public func hide(_ kind: PopinVRWindowKind) {
        update(kind) { $0.isVisible = false }
    }

    public func toggle(_ kind: PopinVRWindowKind) {
        update(kind) { $0.isVisible.toggle() }
    }

    public func move(_ id: UUID, to transform: simd_float4x4) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].worldFromWindow = transform
        onChange?()
    }

    /// Intersects a world-space pointer ray with a window plane and returns normalized
    /// panel coordinates (0...1). This is shared by gaze, controller and hand-ray input.
    public func hitTest(rayOrigin: SIMD3<Float>, rayDirection: SIMD3<Float>) -> (window: PopinVRSpatialWindow, uv: SIMD2<Float>)? {
        for window in windows.reversed() where window.isVisible {
            let transform = window.worldFromWindow
            let origin = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let right = simd_normalize(SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z))
            let up = simd_normalize(SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z))
            let normal = simd_normalize(SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            let denominator = simd_dot(rayDirection, normal)
            guard abs(denominator) > 1e-5 else { continue }
            let distance = simd_dot(origin - rayOrigin, normal) / denominator
            guard distance > 0 else { continue }
            let point = rayOrigin + rayDirection * distance - origin
            let x = simd_dot(point, right) / window.sizeMeters.x + 0.5
            let y = 0.5 - simd_dot(point, up) / window.sizeMeters.y
            if (0...1).contains(x), (0...1).contains(y) {
                return (window, SIMD2<Float>(x, y))
            }
        }
        return nil
    }

    private func update(_ kind: PopinVRWindowKind, _ body: (inout PopinVRSpatialWindow) -> Void) {
        guard let index = windows.firstIndex(where: { $0.kind == kind }) else { return }
        body(&windows[index])
        onChange?()
    }

    private func makeWindow(
        _ kind: PopinVRWindowKind,
        title: String,
        head: simd_float4x4,
        offset: SIMD3<Float>,
        size: SIMD2<Float>,
        visible: Bool = true
    ) -> PopinVRSpatialWindow {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(offset.x, offset.y, offset.z, 1)
        return PopinVRSpatialWindow(
            kind: kind,
            title: title,
            worldFromWindow: head * transform,
            sizeMeters: size,
            isVisible: visible
        )
    }
}
