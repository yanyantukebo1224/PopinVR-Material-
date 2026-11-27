import CoreVideo
import Foundation
import ImageIO
import simd

public struct PopinVRHandTrackingFrame: Sendable {
    public let timestamp: TimeInterval
    public let cameraIntrinsics: simd_float3x3
    public let worldFromCamera: simd_float4x4
    public let hands: [PopinVRHandObservation]
    public let haMeRCrops: [PopinVRHaMeRCrop]
    public let haMeRParameters: [PopinVRHaMeRParameters]
}

/// Bounded asynchronous hand pipeline. It drops stale camera frames rather than building latency.
public final class PopinVRHandTrackingPipeline {
    private let tracker: PopinVRVisionHandTracker
    private let preprocessor = PopinVRHaMeRPreprocessor()
    private let haMeRModel: PopinVRHaMeRCoreMLModel?
    private let queue = DispatchQueue(label: "popinvr.hand.inference", qos: .userInitiative)
    private let lock = NSLock()
    private var busy = false
    private var nextAllowedTimestamp: TimeInterval = 0

    public var maximumInferenceRate: Double
    public var onResult: ((PopinVRHandTrackingFrame) -> Void)?
    public var onError: ((Error) -> Void)?

    public init(
        maximumInferenceRate: Double = 20,
        maximumHands: Int = 2,
        haMeRModel: PopinVRHaMeRCoreMLModel? = nil
    ) {
        self.maximumInferenceRate = max(1, maximumInferenceRate)
        tracker = PopinVRVisionHandTracker(maximumHandCount: maximumHands)
        self.haMeRModel = haMeRModel
    }

    public func submit(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        orientation: CGImagePropertyOrientation = .up,
        cameraIntrinsics: simd_float3x3,
        worldFromCamera: simd_float4x4
    ) {
        lock.lock()
        let interval = 1 / max(maximumInferenceRate, 1)
        guard !busy, timestamp >= nextAllowedTimestamp else {
            lock.unlock()
            return
        }
        busy = true
        nextAllowedTimestamp = timestamp + interval
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.busy = false
                self.lock.unlock()
            }
            do {
                let hands = try self.tracker.detect(in: pixelBuffer, orientation: orientation)
                let crops = try self.preprocessor.crops(from: pixelBuffer, observations: hands)
                var parameters: [PopinVRHaMeRParameters] = []
                if let model = self.haMeRModel {
                    parameters.reserveCapacity(crops.count)
                    for crop in crops {
                        parameters.append(try model.predict(normalizedNCHW: crop.normalizedNCHW))
                    }
                }
                self.onResult?(PopinVRHandTrackingFrame(
                    timestamp: timestamp,
                    cameraIntrinsics: cameraIntrinsics,
                    worldFromCamera: worldFromCamera,
                    hands: hands,
                    haMeRCrops: crops,
                    haMeRParameters: parameters
                ))
            } catch {
                self.onError?(error)
            }
        }
    }
}
