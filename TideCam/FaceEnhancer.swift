import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit
import Vision

/// Vision face-detection + restrained local sharpening.
/// This is face-aware computational processing, NOT a generative face
/// reconstruction model. It deliberately avoids guessing facial features.
struct FaceEnhancer {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func enhance(_ data: Data, zoomFactor: CGFloat = 1) -> Data? {
        guard let original = CGImageSourceCreateWithData(data as CFData, nil),
              let input = CIImage(data: data, options: [.applyOrientationProperty: true]),
              input.extent.width > 32, input.extent.height > 32,
              let cgImage = context.createCGImage(input, from: input.extent) else {
            return nil
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results, !observations.isEmpty else {
            return nil
        }

        let extent = input.extent
        let intensity = min(0.58, 0.28 + max(0, zoomFactor - 1) * 0.035)
        let sharpened = input.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 1.1,
            kCIInputIntensityKey: intensity
        ])

        var result = input
        var processedFaces = 0
        for face in observations.prefix(8) {
            let bounds = face.boundingBox
            let width = extent.width * bounds.width
            let height = extent.height * bounds.height
            guard width >= 30, height >= 30 else { continue }

            let center = CIVector(
                x: extent.minX + extent.width * bounds.midX,
                y: extent.minY + extent.height * bounds.midY
            )
            let innerRadius = min(width, height) * 0.30
            let outerRadius = max(width, height) * 0.78

            let mask = CIFilter.radialGradient()
            mask.center = center
            mask.radius0 = Float(innerRadius)
            mask.radius1 = Float(outerRadius)
            mask.color0 = CIColor.white
            mask.color1 = CIColor.black

            guard let maskImage = mask.outputImage?.cropped(to: extent) else { continue }
            result = sharpened.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: result,
                kCIInputMaskImageKey: maskImage
            ]).cropped(to: extent)
            processedFaces += 1
        }
        guard processedFaces > 0,
              let resultImage = context.createCGImage(result, from: extent) else {
            return nil
        }

        // CIImage above applies EXIF orientation to pixels. Override metadata
        // orientation to upright so Photos does not rotate them twice.
        var metadata = (CGImageSourceCopyPropertiesAtIndex(original, 0, nil) as? [String: Any]) ?? [:]
        metadata[kCGImagePropertyOrientation as String] = 1

        func encode(_ type: CFString) -> Data? {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, type, 1, nil
            ) else { return nil }
            var properties = metadata
            properties[kCGImageDestinationLossyCompressionQuality as String] = 0.98
            CGImageDestinationAddImage(destination, resultImage, properties as CFDictionary)
            return CGImageDestinationFinalize(destination) ? (output as Data) : nil
        }

        return encode(CGImageSourceGetType(original) ?? "public.jpeg" as CFString)
            ?? encode("public.jpeg" as CFString)
    }
}
