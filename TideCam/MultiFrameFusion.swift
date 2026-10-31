import CoreImage
import ImageIO
import UIKit
import Vision

/// Aligns a small set of stills and combines only pixels that remain similar.
///
/// This is computational multi-frame denoising, not neural super-resolution.
/// Translation registration cannot fix parallax or subject motion, so a
/// conservative per-pixel motion mask protects the reference frame.
struct MultiFrameFusion {
    struct Result {
        let data: Data
        let frameCount: Int
    }

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let maximumSupportingFrames = 4

    func fuse(reference: Data, alternatives: [Data]) -> Result? {
        guard !alternatives.isEmpty,
              let original = CIImage(data: reference, options: [.applyOrientationProperty: false]),
              original.extent.width >= 128, original.extent.height >= 128 else {
            return nil
        }

        let extent = original.extent.integral
        let sampleScale = min(1.0, 768.0 / max(extent.width, extent.height))
        let referenceSmall = original.transformed(by: CGAffineTransform(
            scaleX: sampleScale, y: sampleScale
        ))
        guard let referenceCG = context.createCGImage(referenceSmall, from: referenceSmall.extent) else {
            return nil
        }

        var accumulated = original
        var frameCount = 1

        for candidateData in alternatives.prefix(maximumSupportingFrames) {
            autoreleasepool {
                guard let candidate = CIImage(data: candidateData, options: [.applyOrientationProperty: false]),
                      abs(candidate.extent.width - extent.width) < 1,
                      abs(candidate.extent.height - extent.height) < 1 else {
                    return
                }

                let candidateSmall = candidate.transformed(by: CGAffineTransform(
                    scaleX: sampleScale, y: sampleScale
                ))
                guard let candidateCG = context.createCGImage(candidateSmall, from: candidateSmall.extent) else {
                    return
                }

                // Vision reports a transform mapping floating -> reference.
                let request = VNTranslationalImageRegistrationRequest(
                    targetedCGImage: candidateCG,
                    options: [:]
                )
                let handler = VNImageRequestHandler(cgImage: referenceCG, options: [:])
                guard (try? handler.perform([request])) != nil,
                      let alignment = request.results?.first?.alignmentTransform,
                      alignment.tx.isFinite, alignment.ty.isFinite else {
                    return
                }

                let tx = alignment.tx / sampleScale
                let ty = alignment.ty / sampleScale
                let maximumShift = min(extent.width, extent.height) * 0.02
                guard abs(tx) < maximumShift, abs(ty) < maximumShift else {
                    return
                }

                let aligned = candidate.transformed(by: CGAffineTransform(
                    translationX: tx, y: ty
                ))
                // Ignore frames with excessive translation or missing borders.
                let overlap = aligned.extent.intersection(extent)
                guard overlap.width >= extent.width * 0.98,
                      overlap.height >= extent.height * 0.98 else {
                    return
                }

                // White = nearly identical; black = movement / inconsistent
                // detail. The mask is soft to avoid noticeable boundaries.
                let difference = aligned.applyingFilter("CIDifferenceBlendMode", parameters: [
                    kCIInputBackgroundImageKey: original
                ])
                let mask = difference.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: -1.2756, y: -4.2912, z: -0.4332, w: 0),
                    "inputGVector": CIVector(x: -1.2756, y: -4.2912, z: -0.4332, w: 0),
                    "inputBVector": CIVector(x: -1.2756, y: -4.2912, z: -0.4332, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
                ]).cropped(to: extent)

                // Progressively average accepted frames; keep the sharpest
                // frame wherever the motion mask detects disagreement.
                let mixed = aligned.applyingFilter("CIMix", parameters: [
                    kCIInputBackgroundImageKey: accumulated,
                    "inputAmount": 1.0 / Double(frameCount + 1)
                ])
                accumulated = mixed.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: accumulated,
                    "inputMaskImage": mask
                ]).cropped(to: extent)
                frameCount += 1
            }
        }

        guard frameCount > 1,
              let outputCG = context.createCGImage(accumulated, from: extent),
              let source = CGImageSourceCreateWithData(reference as CFData, nil) else {
            return nil
        }

        let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        let outputType = CGImageSourceGetType(source) ?? "public.jpeg" as CFString
        let result = NSMutableData()

        func write(as type: CFString) -> Data? {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type, 1, nil) else {
                return nil
            }
            var properties = (metadata as? [String: Any]) ?? [:]
            properties[kCGImageDestinationLossyCompressionQuality as String] = 0.98
            CGImageDestinationAddImage(destination, outputCG, properties as CFDictionary)
            return CGImageDestinationFinalize(destination) ? (data as Data) : nil
        }

        // Fall back to JPEG when a device's source codec cannot be exported.
        let encoded = write(as: outputType) ?? write(as: "public.jpeg" as CFString)
        guard let encoded else { return nil }
        _ = result // The encoded CFData buffer is returned from write(as:).
        return Result(data: encoded, frameCount: frameCount)
    }
}
