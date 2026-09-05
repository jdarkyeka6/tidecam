import Accelerate
import CoreImage
import UIKit

/// CPU-side v0.1 Detail analysis. This deliberately does not pretend to be
/// super-resolution yet: it rejects weak frames and chooses the strongest
/// source image before the alignment/fusion pipeline lands.
struct DetailProcessor {
    struct Candidate {
        let data: Data
        let image: UIImage
        let sharpness: Double
        let brightness: Double
        let score: Double
    }

    private let context = CIContext(options: [.cacheIntermediates: false])

    func bestCandidate(from frames: [Data]) -> Candidate? {
        frames.compactMap(analyse).max { $0.score < $1.score }
    }

    private func analyse(_ data: Data) -> Candidate? {
        guard let uiImage = UIImage(data: data),
              let ciImage = CIImage(data: data) else { return nil }

        let extent = ciImage.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }

        // CIAreaAverage gives a cheap exposure sanity signal.
        let average = ciImage
            .applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])

        var rgba = [UInt8](repeating: 0, count: 4)
        context.render(average,
                       toBitmap: &rgba,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        let brightness = (Double(rgba[0]) + Double(rgba[1]) + Double(rgba[2])) / (3 * 255)

        guard let cgImage = context.createCGImage(ciImage, from: extent) else { return nil }
        let sharpness = laplacianVariance(cgImage)

        // Penalise frames approaching clipped black/white while strongly
        // rewarding local edge energy. Values are relative within a burst.
        let exposurePenalty = abs(brightness - 0.5) * 0.25
        let score = log1p(sharpness) - exposurePenalty
        return Candidate(data: data, image: uiImage, sharpness: sharpness, brightness: brightness, score: score)
    }

    private func laplacianVariance(_ image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        guard width > 2, height > 2 else { return 0 }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(data: &pixels,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum = 0.0
        var sumSquares = 0.0
        var count = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let lap = 4.0 * Double(pixels[i])
                    - Double(pixels[i - 1]) - Double(pixels[i + 1])
                    - Double(pixels[i - width]) - Double(pixels[i + width])
                sum += lap
                sumSquares += lap * lap
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let mean = sum / count
        return max(0, (sumSquares / count) - mean * mean)
    }
}
