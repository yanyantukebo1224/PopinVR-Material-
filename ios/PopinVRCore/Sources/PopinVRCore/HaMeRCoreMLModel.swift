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
        }), let constraint = input.value.multiArrayConstraint else {
            throw PopinVRHaMeRError.missingMultiArrayInput
        }
        inputName = input.key
        inputShape = constraint.shape.map { $0.intValue }
    }

    public static func compileAndLoad(
        modelPackageAt packageURL: URL,
        computeUnits: MLComputeUnits = .cpuAndNeuralEngine
    ) throws -> PopinVRHaMeRCoreMLModel {
        let compiledURL = try MLModel.compileModel(at: packageURL)
        return try PopinVRHaMeRCoreMLModel(compiledModelAt: compiledURL, computeUnits: computeUnits)
    }

    /// Input is the normalized 3×256×256 RGB crop. Lower-resolution HaMeR variants receive
    /// the center-width crop and resize used by fasthamer's Python adapter.
    public func predict(normalizedNCHW: [Float]) throws -> PopinVRHaMeRParameters {
        let cropCount = 3 * 256 * 256
        guard normalizedNCHW.count == cropCount else {
            throw PopinVRHaMeRError.invalidInputCount(expected: cropCount, actual: normalizedNCHW.count)
        }
        let modelInput = try Self.adaptCrop(normalizedNCHW, to: inputShape)
        let input = try MLMultiArray(
            shape: inputShape.map { NSNumber(value: $0) },
            dataType: .float32
        )
        let destination = input.dataPointer.bindMemory(to: Float.self, capacity: input.count)
        modelInput.withUnsafeBufferPointer { source in
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

    private static func adaptCrop(_ crop: [Float], to shape: [Int]) throws -> [Float] {
        guard shape.count == 4, shape[0] == 1, shape[1] == 3,
              shape[2] > 0, shape[3] > 0 else {
            throw PopinVRHaMeRError.unsupportedInputShape(shape)
        }
        let height = shape[2], width = shape[3]
        if height == 256 && width == 256 { return crop }

        // Python fasthamer slices columns 32..<224 before resizing the 192×256 center crop.
        let sourceWidth = 192
        let sourceHeight = 256
        let sourcePlane = 256 * 256
        var output = Array(repeating: Float.zero, count: 3 * height * width)

        for channel in 0..<3 {
            for y in 0..<height {
                let sourceY = (Float(y) + 0.5) * Float(sourceHeight) / Float(height) - 0.5
                let y0 = max(0, min(sourceHeight - 1, Int(floor(sourceY))))
                let y1 = min(sourceHeight - 1, y0 + 1)
                let fy = max(0, min(1, sourceY - Float(y0)))
                for x in 0..<width {
                    let sourceX = (Float(x) + 0.5) * Float(sourceWidth) / Float(width) - 0.5
                    let x0 = max(0, min(sourceWidth - 1, Int(floor(sourceX))))
                    let x1 = min(sourceWidth - 1, x0 + 1)
                    let fx = max(0, min(1, sourceX - Float(x0)))
                    let base = channel * sourcePlane
                    let a = crop[base + y0 * 256 + x0 + 32]
                    let b = crop[base + y0 * 256 + x1 + 32]
                    let c = crop[base + y1 * 256 + x0 + 32]
                    let d = crop[base + y1 * 256 + x1 + 32]
                    let top = a * (1 - fx) + b * fx
                    let bottom = c * (1 - fx) + d * fx
                    output[channel * height * width + y * width + x] = top * (1 - fy) + bottom * fy
                }
            }
        }
        return output
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
    case unsupportedInputShape([Int])
}
