import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onFocus: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.previewView = view
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFocus: onFocus)
    }

    final class Coordinator: NSObject {
        let onFocus: (CGPoint) -> Void
        weak var previewView: PreviewView?

        init(onFocus: @escaping (CGPoint) -> Void) {
            self.onFocus = onFocus
        }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view = previewView else { return }
            let point = recognizer.location(in: view)
            let devicePoint = view.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: point)
            onFocus(devicePoint)
            view.showFocusIndicator(at: point)
        }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    func showFocusIndicator(at point: CGPoint) {
        let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))
        indicator.center = point
        indicator.layer.borderWidth = 1.5
        indicator.layer.borderColor = UIColor.systemYellow.cgColor
        indicator.layer.cornerRadius = 8
        indicator.alpha = 0
        addSubview(indicator)

        UIView.animate(withDuration: 0.15, animations: {
            indicator.alpha = 1
            indicator.transform = CGAffineTransform(scaleX: 0.78, y: 0.78)
        }) { _ in
            UIView.animate(withDuration: 0.35, delay: 0.45, options: [], animations: {
                indicator.alpha = 0
            }) { _ in indicator.removeFromSuperview() }
        }
    }
}
