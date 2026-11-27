import CoreML
import Foundation

public struct PopinVRHaMeRParameters: Sendable {
    public let camera: [Float]
    public let globalOrientation: [Float]
    public let handPose: [Float]
    public let shapeBetas: [Float]

    public init(camera: [Float], globalOrientation: [Float], handPose: [Float], shapeBetas: [Float]) {
        self.camera = camera
        self.globalOrientation = globalOrientation
        self.handPose = handPose
        self.shapeBetas = shapeBetas
    }
}

/// Native Core ML adapter for the fasthamer HaMeR parameter model.
/// Input is an already-cropped, RGB, ImageNet-normalized NCHW tensor. Detection and exact
/// Python-equivalent crop preprocessing are separate stages and must be validated independently.
public final class PopinVRHaMeRCoreMLModel {
    private let model: MLModel
    private let inputName: String
    private let inputShape: [Int]

    public var expectedInputShape: [Int] { inputShape }

    public init(compiledModelAt url: URL, computeUnits: MLComputeUnits = .cpuAndNeuralEngine) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: url, configuration: configuration)

        guard let input = model.modelDescription.inputDescriptionsByName.first(where: {
            $0.value.type == .multiArray
        }),
        let constraint = input.value.multiArrayConstraint else {
            throw PopinVRHaMeRError.missingMultiArrayInput
        }
        inputName = input.key
        inputShape = constraint.shape.map { $0.intValue }
    }

    /// Compile a downloaded .mlpackage once, then load its compiled Core ML representation.
    /// The app should verify the downloaded archive's checksum before calling this method.
    public static func compileAndLoad(
        modelPackageAt packageURL: URL,
        computeUnits: MLComputeUnits = .cpuAndNeuralEngine
    ) throws -> PopinVRHaMeRCoreMLModel {
        let compiledURL = try MLModel.compileModel(at: packageURL)
        return try PopinVRHaMeRCoreMLModel(compiledModelAt: compiledURL, computeUnits: computeUnits)
    }

    /// Runs one HaMeR crop. The tensor must match the model's declared shape exactly.
    public func predict(normalizedNCHW: [Float]) throws -> PopinVRHaMeRParameters {
        let expectedCount = inputShape.reduce(1, *)
        guard normalizedNCHW.count == expectedCount else {
            throw PopinVRHaMeRError.invalidInputCount(expected: expectedCount, actual: normalizedNCHW.count)
        }

        let input = try MLMultiArray(
            shape: inputShape.map { NSNumber(value: $0) },
            dataType: .float32
        )
        let destination = input.dataPointer.bindMemory(to: Float.self, capacity: input.count)
        normalizedNCHW.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                destination.update(from: base, count: source.count)
            }
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(multiArray: input)
        ])
        let output = try model.prediction(from: provider)

        return PopinVRHaMeRParameters(
            camera: try Self.readArray("cam", from: output),
            globalOrientation: try Self.readArray("global_orient", from: output),
            handPose: try Self.readArray("hand_pose", from: output),
            shapeBetas: try Self.readArray("betas", from: output)
        )
    }

    private static func readArray(_ name: String, from provider: MLFeatureProvider) throws -> [Float] {
        guard let array = provider.featureValue(for: name)?.multiArrayValue else {
            throw PopinVRHaMeRError.missingOutput(name)
        }
        return (0..<array.count).map { array[$0].floatValue }
    }
}

public enum PopinVRHaMeRError: Error {
    case missingMultiArrayInput
    case invalidInputCount(expected: Int, actual: Int)
    case missingOutput(String)
}
