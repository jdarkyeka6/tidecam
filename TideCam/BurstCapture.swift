import AVFoundation
import CoreImage
import Foundation
import Vision

/// A distinct delegate for each overlapping still capture. AVFoundation may
/// finish captures out of order; the completion always belongs to its request.
final class BurstFrameCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let onCompletion: (Data?, Error?) -> Void
    private var data: Data?
    private var processingError: Error?

    init(onCompletion: @escaping (Data?, Error?) -> Void) {
        self.onCompletion = onCompletion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        processingError = error
        if error == nil { data = photo.fileDataRepresentation() }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        onCompletion(data, error ?? processingError)
        data = nil
    }
}

/// Best-shot discovery happens AFTER capture. It must never stall the shutter,
/// and never requires retaining every full-resolution image in memory.
struct BurstHighlightPicker {
    struct Result {
        let data: Data
        let evaluatedFrames: Int
    }

    static func sampleIndices(total: Int, limit: Int = 36) -> [Int] {
        guard total > 0, limit > 0 else { return [] }
        let count = min(total, limit)
        guard count > 1 else { return [0] }
        return (0..<count).map { index in
            index * (total - 1) / (count - 1)
        }
    }

    func select(from urls: [URL], maxSamples: Int = 36) -> Result? {
        guard !urls.isEmpty else { return nil }
        let processor = DetailProcessor()
        var leaders: [DetailProcessor.ScoredFrame] = []
        var evaluated = 0

        for index in Self.sampleIndices(total: urls.count, limit: maxSamples) {
            autoreleasepool {
                guard let data = try? Data(contentsOf: urls[index]),
                      let candidate = processor.rankedFrames(from: [data], limit: 1).first else {
                    return
                }
                evaluated += 1
                leaders.append(candidate)
                leaders.sort { $0.score > $1.score }
                if leaders.count > 4 { leaders.removeLast() }
            }
        }
        guard !leaders.isEmpty else { return nil }

        // Apple's Vision detects faces only on the top 4 contenders, AFTER
        // shutter release. Small bonuses favour visible faces in similarly
        // sharp shots without prioritising faces over serious motion blur.
        let context = CIContext(options: [.cacheIntermediates: false])
        var chosen = leaders[0]
        var bestScore = -Double.infinity
        for candidate in leaders {
            let visibleFaces = faceConfidence(
                in: candidate.data, context: context
            )
            let totalScore = candidate.score + visibleFaces
            if totalScore > bestScore {
                chosen = candidate
                bestScore = totalScore
            }
        }
        return Result(data: chosen.data, evaluatedFrames: evaluated)
    }

    private func faceConfidence(in data: Data, context: CIContext) -> Double {
        guard let source = CIImage(data: data) else { return 0 }
        let largestDimension = max(source.extent.width, source.extent.height)
        guard largestDimension > 0 else { return 0 }
        let scale = min(1.0, 640.0 / largestDimension)
        let sampled = source.transformed(by: CGAffineTransform(
            scaleX: scale, y: scale
        ))
        guard let image = context.createCGImage(sampled, from: sampled.extent) else {
            return 0
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let faces = request.results else { return 0 }

        let usable = faces.filter {
            $0.boundingBox.width * $0.boundingBox.height > 0.006
        }
        return min(0.24, Double(usable.count) * 0.08)
    }
}
