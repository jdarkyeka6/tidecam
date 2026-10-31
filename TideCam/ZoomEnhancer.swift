import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

/// Conservative, on-device digital-zoom cleanup. This is not a trained AI
/// super-resolution model and does not invent missing optical detail.
/// Keep the source capture intact so users can compare or reprocess it.
struct ZoomEnhancer {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func enhance(_ data: Data, zoomFactor: CGFloat) -> Data? {
        guard zoomFactor.isFinite, zoomFactor >= 1.5,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let input = CIImage(data: data, options: [.applyOrientationProperty: false]),
              input.extent.width > 0, input.extent.height > 0 else {
            return nil
        }

        // Do not enlarge the image here. Enlarging a digital crop adds
        // pixels, not detail, and makes misleading resolution claims.
        let strength = Float(min(max((zoomFactor - 1.5) / 8.5, 0), 1))
        let noise = CIFilter.noiseReduction()
        noise.inputImage = input
        noise.noiseLevel = 0.012 + (0.011 * strength)
        noise.sharpness = 0.35

        let sharpening = CIFilter.sharpenLuminance()
        sharpening.inputImage = noise.outputImage ?? input
        sharpening.sharpness = 0.25 + (0.12 * strength)

        guard let output = sharpening.outputImage,
              let cgImage = context.createCGImage(output, from: input.extent) else {
            return nil
        }

        // Copy original metadata, including EXIF orientation, GPS and date.
        // The CI input deliberately ignores orientation so it isn't rotated twice.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        let sourceType = CGImageSourceGetType(source)
        let destinationType = sourceType ?? UTType.jpeg.identifier as CFString

        func encode(as type: CFString) -> Data? {
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, type, 1, nil) else {
                return nil
            }
            var options = (properties as? [String: Any]) ?? [:]
            options[kCGImageDestinationLossyCompressionQuality as String] = 0.96
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return result as Data
        }

        return encode(as: destinationType) ?? encode(as: UTType.jpeg.identifier as CFString)
    }
}
