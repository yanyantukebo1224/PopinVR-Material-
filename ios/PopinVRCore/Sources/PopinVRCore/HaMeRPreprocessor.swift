import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

public struct PopinVRHaMeRCrop: Sendable {
    public let normalizedNCHW: [Float]
    public let boxCenterPixels: SIMD2<Float>
    public let boxSizePixels: Float
    public let imageSizePixels: SIMD2<Float>
    public let isRightHand: Bool
}

/// Converts an ARKit frame and Vision hand landmarks into normalized HaMeR crops.
/// The result must still be compared with Python fasthamer golden tensors before parity is claimed.
public final class PopinVRHaMeRPreprocessor {
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private static let side = 256
    private static let mean = SIMD3<Float>(0.485, 0.456, 0.406)
    private static let std = SIMD3<Float>(0.229, 0.224, 0.225)

    public init() {}

    public func crops(
        from pixelBuffer: CVPixelBuffer,
        observations: [PopinVRHandObservation]
    ) throws -> [PopinVRHaMeRCrop] {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { throw PopinVRPreprocessError.invalidImage }

        let rgbBuffer = try makeBGRA(pixelBuffer, width: width, height: height)
        CVPixelBufferLockBaseAddress(rgbBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(rgbBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(rgbBuffer) else {
            throw PopinVRPreprocessError.invalidImage
        }

        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(rgbBuffer)
        var result: [PopinVRHaMeRCrop] = []

        for observation in observations {
            guard let bounds = Self.bounds(of: observation, width: width, height: height) else { continue }
            let center = SIMD2<Float>(Float(bounds.midX), Float(bounds.midY))
            let boxWidth = Float(bounds.width) * 2
            let boxHeight = Float(bounds.height) * 2
            // HaMeR expands the detector box to its 192:256 aspect, then takes a square patch.
            let boxSize = max(boxHeight, boxWidth / 0.75)
            guard boxSize.isFinite, boxSize > 2 else { continue }

            let isRight = observation.isRightHand ?? true
            let tensor = Self.makeTensor(
                bytes: bytes,
                bytesPerRow: bytesPerRow,
                imageWidth: width,
                imageHeight: height,
                center: center,
                boxSize: boxSize,
                mirrorHorizontally: !isRight
            )
            result.append(PopinVRHaMeRCrop(
                normalizedNCHW: tensor,
                boxCenterPixels: center,
                boxSizePixels: boxSize,
                imageSizePixels: SIMD2<Float>(Float(width), Float(height)),
                isRightHand: isRight
            ))
        }
        return result
    }

    private func makeBGRA(_ source: CVPixelBuffer, width: Int, height: Int) throws -> CVPixelBuffer {
        var output: CVPixelBuffer?
        let attributes: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &output
        )
        guard status == kCVReturnSuccess, let output else {
            throw PopinVRPreprocessError.pixelBufferCreationFailed(status)
        }
        let image = CIImage(cvPixelBuffer: source)
        context.render(
            image,
            to: output,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return output
    }

    private static func bounds(
        of observation: PopinVRHandObservation,
        width: Int,
        height: Int
    ) -> CGRect? {
        let points = observation.points.filter { $0.confidence > 0.05 }
        guard points.count >= 5 else { return nil }
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        // Vision normalized points use a bottom-left origin; pixel buffers use top-left rows.
        let x0 = minX * Float(width)
        let x1 = maxX * Float(width)
        let y0 = (1 - maxY) * Float(height)
        let y1 = (1 - minY) * Float(height)
        guard x1 > x0, y1 > y0 else { return nil }
        return CGRect(x: CGFloat(x0), y: CGFloat(y0), width: CGFloat(x1 - x0), height: CGFloat(y1 - y0))
    }

    private static func makeTensor(
        bytes: UnsafePointer<UInt8>,
        bytesPerRow: Int,
        imageWidth: Int,
        imageHeight: Int,
        center: SIMD2<Float>,
        boxSize: Float,
        mirrorHorizontally: Bool
    ) -> [Float] {
        let pixelCount = side * side
        var output = Array(repeating: Float.zero, count: 3 * pixelCount)
        let scale = boxSize / Float(side)

        for y in 0..<side {
            let sourceY = center.y + (Float(y) - Float(side) * 0.5) * scale
            for x in 0..<side {
                let deltaX = (Float(x) - Float(side) * 0.5) * scale
                let sourceX = center.x + (mirrorHorizontally ? -deltaX : deltaX)
                let rgb = sampleBGRA(
                    bytes, bytesPerRow: bytesPerRow, width: imageWidth, height: imageHeight,
                    x: sourceX, y: sourceY
                )
                let index = y * side + x
                output[index] = (rgb.x / 255 - mean.x) / std.x
                output[pixelCount + index] = (rgb.y / 255 - mean.y) / std.y
                output[2 * pixelCount + index] = (rgb.z / 255 - mean.z) / std.z
            }
        }
        return output
    }

    private static func sampleBGRA(
        _ bytes: UnsafePointer<UInt8>,
        bytesPerRow: Int,
        width: Int,
        height: Int,
        x: Float,
        y: Float
    ) -> SIMD3<Float> {
        let px = x
        let py = y
        let x0 = Int(floor(px)), y0 = Int(floor(py))
        let fx = px - Float(x0), fy = py - Float(y0)

        func channel(_ ix: Int, _ iy: Int, _ component: Int) -> Float {
            guard ix >= 0, iy >= 0, ix < width, iy < height else { return 0 }
            return Float(bytes[iy * bytesPerRow + ix * 4 + component])
        }
        func interpolate(_ component: Int) -> Float {
            let a = channel(x0, y0, component)
            let b = channel(x0 + 1, y0, component)
            let c = channel(x0, y0 + 1, component)
            let d = channel(x0 + 1, y0 + 1, component)
            return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
        }
        return SIMD3(interpolate(2), interpolate(1), interpolate(0))
    }
}

public enum PopinVRPreprocessError: Error {
    case invalidImage
    case pixelBufferCreationFailed(CVReturn)
}
