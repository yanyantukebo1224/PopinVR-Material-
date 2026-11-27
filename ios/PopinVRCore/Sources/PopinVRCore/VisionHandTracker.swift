import Foundation
import Vision
import ImageIO
import CoreVideo

public struct PopinVRHandPoint: Sendable {
    public let name: String
    /// Vision normalized image coordinates (origin at lower-left).
    public let x: Float
    public let y: Float
    public let confidence: Float
}

public struct PopinVRHandObservation: Sendable {
    public let isRightHand: Bool?
    public let confidence: Float
    public let points: [PopinVRHandPoint]
}

/// iOS-native 2D hand-pose frontend.
/// This is a detector/keypoint source for the later HaMeR/SOMA-X 3D mesh stage;
/// Vision keypoints are NOT a 3D hand mesh and must not be rendered as one.
public final class PopinVRVisionHandTracker {
    private let request: VNDetectHumanHandPoseRequest

    public init(maximumHandCount: Int = 2) {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = max(1, min(maximumHandCount, 2))
        request.revision = VNDetectHumanHandPoseRequestRevision1
        self.request = request
    }

    public func detect(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [PopinVRHandObservation] {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        try handler.perform([request])

        return (request.results ?? []).map { observation in
            let recognized = (try? observation.recognizedPoints(.all)) ?? [:]
            let points = recognized.compactMap { key, point -> PopinVRHandPoint? in
                guard point.confidence > 0.05 else { return nil }
                return PopinVRHandPoint(
                    name: String(describing: key),
                    x: Float(point.location.x),
                    y: Float(point.location.y),
                    confidence: Float(point.confidence)
                )
            }.sorted { $0.name < $1.name }

            return PopinVRHandObservation(
                isRightHand: observation.chiralityValue,
                confidence: Float(observation.confidence),
                points: points
            )
        }
    }
}

private extension VNHumanHandPoseObservation {
    var chiralityValue: Bool? {
        switch chirality {
        case .left: return false
        case .right: return true
        @unknown default: return nil
        }
    }
}
