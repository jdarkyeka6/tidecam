import AVFoundation
import Foundation

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
        var winner: DetailProcessor.ScoredFrame?
        var evaluated = 0
        for index in Self.sampleIndices(total: urls.count, limit: maxSamples) {
            autoreleasepool {
                guard let data = try? Data(contentsOf: urls[index]),
                      let candidate = processor.rankedFrames(from: [data], limit: 1).first else {
                    return
                }
                evaluated += 1
                if winner == nil || candidate.score > winner!.score {
                    winner = candidate
                }
            }
        }
        guard let winner else { return nil }
        return Result(data: winner.data, evaluatedFrames: evaluated)
    }
}
