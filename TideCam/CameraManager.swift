import AVFoundation
import Photos
import SwiftUI

@MainActor
final class CameraManager: NSObject, ObservableObject {
    enum FlashMode: CaseIterable {
        case off, auto, on

        var avMode: AVCaptureDevice.FlashMode {
            switch self {
            case .off: return .off
            case .auto: return .auto
            case .on: return .on
            }
        }

        var symbol: String {
            switch self {
            case .off: return "bolt.slash.fill"
            case .auto: return "bolt.badge.a.fill"
            case .on: return "bolt.fill"
            }
        }
    }

    let session = AVCaptureSession()

    @Published var isAuthorized = false
    @Published var isConfigured = false
    @Published var isCapturing = false
    @Published var flashMode: FlashMode = .auto
    @Published var lastPhoto: UIImage?
    @Published var errorMessage: String?

    private let sessionQueue = DispatchQueue(label: "com.tidecam.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back

    override init() {
        super.init()
        Task { await requestPermissionAndConfigure() }
    }

    func requestPermissionAndConfigure() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool

        switch status {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            granted = false
        }

        isAuthorized = granted
        guard granted else { return }
        configureSession()
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            do {
                guard let device = self.bestDevice(for: self.position) else {
                    throw CameraError.noCamera
                }

                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw CameraError.cannotAddInput }
                self.session.addInput(input)
                self.videoInput = input

                guard self.session.canAddOutput(self.photoOutput) else { throw CameraError.cannotAddOutput }
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality

                self.session.commitConfiguration()
                self.session.startRunning()

                Task { @MainActor in self.isConfigured = true }
            } catch {
                self.session.commitConfiguration()
                Task { @MainActor in self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInTrueDepthCamera, .builtInWideAngleCamera]

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: position
        ).devices.first
    }

    func capturePhoto() {
        guard isConfigured, !isCapturing else { return }
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        if let device = videoInput?.device, device.hasFlash {
            settings.flashMode = flashMode.avMode
        }
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func cycleFlash() {
        switch flashMode {
        case .off: flashMode = .auto
        case .auto: flashMode = .on
        case .on: flashMode = .off
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, let currentInput = self.videoInput else { return }
            let newPosition: AVCaptureDevice.Position = self.position == .back ? .front : .back
            guard let device = self.bestDevice(for: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: device) else { return }

            self.session.beginConfiguration()
            self.session.removeInput(currentInput)

            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
                self.position = newPosition
            } else {
                self.session.addInput(currentInput)
            }

            self.session.commitConfiguration()
        }
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }

    enum CameraError: LocalizedError {
        case noCamera, cannotAddInput, cannotAddOutput
        var errorDescription: String? {
            switch self {
            case .noCamera: return "No compatible camera was found."
            case .cannotAddInput: return "TideCam couldn't connect to the camera."
            case .cannotAddOutput: return "TideCam couldn't configure photo capture."
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            Task { @MainActor in
                self.errorMessage = error.localizedDescription
                self.isCapturing = false
            }
            return
        }

        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            Task { @MainActor in self.isCapturing = false }
            return
        }

        Task { @MainActor in
            self.lastPhoto = image
            self.isCapturing = false
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
        }
    }
}
