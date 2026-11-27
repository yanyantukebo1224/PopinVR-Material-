import ARKit
import Foundation
import CoreVideo
import simd

public enum PopinVRTrackingQuality: Sendable, Equatable {
    case normal
    case limited
    case unavailable
}

public struct PopinVRHeadPose: Sendable {
    public let timestamp: TimeInterval
    /// ARKit camera pose: camera-local +X right, +Y up, -Z forward.
    public let worldFromCamera: simd_float4x4
    public let quality: PopinVRTrackingQuality

    public init(timestamp: TimeInterval, worldFromCamera: simd_float4x4, quality: PopinVRTrackingQuality) {
        self.timestamp = timestamp
        self.worldFromCamera = worldFromCamera
        self.quality = quality
    }
}

/// Owns the ARKit world-tracking session used as PopinVR's 6DoF head-pose source.
/// The session must be started while the app is foregrounded and camera permission is granted.
public final class PopinVRHeadTracker: NSObject, ARSessionDelegate {
    public let session = ARSession()

    private let lock = NSLock()
    private var storedPose: PopinVRHeadPose?
    /// Receives ARKit camera frames on the session delegate queue. Consumers should enqueue work and return quickly.
    public var onFrame: ((CVPixelBuffer, TimeInterval, simd_float3x3, simd_float4x4) -> Void)?
    private let callbackQueue = DispatchQueue(label: "popinvr.arkit.delegate", qos: .userInteractive)

    public override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = callbackQueue
    }

    public var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    public func start() throws {
        guard isSupported else {
            throw PopinVRHeadTrackerError.worldTrackingUnavailable
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = []
        configuration.environmentTexturing = .none
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    public func pause() {
        session.pause()
        lock.lock()
        storedPose = nil
        lock.unlock()
    }

    public func latestPose() -> PopinVRHeadPose? {
        lock.lock()
        defer { lock.unlock() }
        return storedPose
    }

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let quality: PopinVRTrackingQuality
        switch frame.camera.trackingState {
        case .normal:
            quality = .normal
        case .notAvailable:
            quality = .unavailable
        case .limited:
            quality = .limited
        }
        let pose = PopinVRHeadPose(
            timestamp: frame.timestamp,
            worldFromCamera: frame.camera.transform,
            quality: quality
        )
        lock.lock()
        storedPose = pose
        lock.unlock()
        onFrame?(frame.capturedImage, frame.timestamp, frame.camera.intrinsics, frame.camera.transform)
    }
}

public enum PopinVRHeadTrackerError: Error {
    case worldTrackingUnavailable
}
