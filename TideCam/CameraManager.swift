import AVFoundation
import Photos
import SwiftUI

@MainActor
final class CameraManager: NSObject, ObservableObject {
    enum FlashMode: CaseIterable {
        case off, auto, on
        var avMode: AVCaptureDevice.FlashMode { self == .off ? .off : (self == .auto ? .auto : .on) }
        var symbol: String { self == .off ? "bolt.slash.fill" : (self == .auto ? "bolt.badge.a.fill" : "bolt.fill") }
    }

    let session = AVCaptureSession()
    @Published var isAuthorized = false
    @Published var isConfigured = false
    @Published var isCapturing = false
    @Published var flashMode: FlashMode = .auto
    @Published var lastPhoto: UIImage?
    @Published var errorMessage: String?
    @Published var capabilities = CameraCapabilities()
    @Published var rawEnabled = false
    @Published var iso: Float = 100
    @Published var focus: Float = 0.5
    @Published var detailProgress: Double = 0

    private let sessionQueue = DispatchQueue(label: "com.tidecam.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var detailFramesRemaining = 0
    private var detailFrameData: [Data] = []

    override init() {
        super.init()
        Task { await requestPermissionAndConfigure() }
    }

    func requestPermissionAndConfigure() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        switch status {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
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
                guard let device = self.bestDevice(for: self.position) else { throw CameraError.noCamera }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw CameraError.cannotAddInput }
                self.session.addInput(input)
                self.videoInput = input
                guard self.session.canAddOutput(self.photoOutput) else { throw CameraError.cannotAddOutput }
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                self.session.commitConfiguration()
                self.session.startRunning()
                self.publishCapabilities(for: device)
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
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position).devices.first
    }

    private func publishCapabilities(for device: AVCaptureDevice) {
        let caps = CameraCapabilities(
            supportsRAW: !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty,
            supportsManualFocus: device.isFocusModeSupported(.locked),
            supportsCustomExposure: device.isExposureModeSupported(.custom),
            supportsTorch: device.hasTorch,
            supportsDepth: device.activeFormat.supportedDepthDataFormats.isEmpty == false,
            minimumISO: device.activeFormat.minISO,
            maximumISO: device.activeFormat.maxISO
        )
        Task { @MainActor in
            self.capabilities = caps
            self.iso = min(max(100, caps.minimumISO), caps.maximumISO)
        }
    }

    func capturePhoto() {
        guard isConfigured, !isCapturing else { return }
        isCapturing = true
        let settings: AVCapturePhotoSettings
        if rawEnabled, let rawType = photoOutput.availableRawPhotoPixelFormatTypes.first {
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawType)
        } else {
            settings = AVCapturePhotoSettings()
        }
        if let device = videoInput?.device, device.hasFlash { settings.flashMode = flashMode.avMode }
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func captureDetailBurst(frameCount: Int = 8) {
        guard isConfigured, !isCapturing else { return }
        detailFramesRemaining = max(2, frameCount)
        detailFrameData.removeAll(keepingCapacity: true)
        detailProgress = 0
        isCapturing = true
        captureNextDetailFrame()
    }

    private func captureNextDetailFrame() {
        guard detailFramesRemaining > 0 else {
            finishDetailBurst()
            return
        }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .speed
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func finishDetailBurst() {
        // v0.1 stores the sharpest candidate. Later versions align and fuse the entire stack.
        let candidates = detailFrameData.compactMap { data -> (Data, UIImage)? in
            guard let image = UIImage(data: data) else { return nil }
            return (data, image)
        }
        if let best = candidates.max(by: { sharpnessScore($0.1) < sharpnessScore($1.1) }) {
            lastPhoto = best.1
            saveToLibrary(best.0)
        }
        detailFrameData.removeAll()
        detailProgress = 1
        isCapturing = false
    }

    private func sharpnessScore(_ image: UIImage) -> CGFloat {
        // Cheap v0.1 heuristic: favour larger, information-rich encoded frames. The fusion engine replaces this.
        image.size.width * image.size.height
    }

    func setISO(_ value: Float) {
        iso = value
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device, device.isExposureModeSupported(.custom) else { return }
            do {
                try device.lockForConfiguration()
                let clamped = min(max(value, device.activeFormat.minISO), device.activeFormat.maxISO)
                device.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: clamped)
                device.unlockForConfiguration()
            } catch { }
        }
    }

    func setFocus(_ value: Float) {
        focus = value
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device, device.isFocusModeSupported(.locked) else { return }
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: min(max(value, 0), 1))
                device.unlockForConfiguration()
            } catch { }
        }
    }

    func cycleFlash() {
        switch flashMode { case .off: flashMode = .auto; case .auto: flashMode = .on; case .on: flashMode = .off }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, let currentInput = self.videoInput else { return }
            let newPosition: AVCaptureDevice.Position = self.position == .back ? .front : .back
            guard let device = self.bestDevice(for: newPosition), let newInput = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(currentInput)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput); self.videoInput = newInput; self.position = newPosition
                self.publishCapabilities(for: device)
            } else { self.session.addInput(currentInput) }
            self.session.commitConfiguration()
        }
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = devicePoint; device.focusMode = .autoFocus }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = devicePoint; device.exposureMode = .continuousAutoExposure }
                device.unlockForConfiguration()
            } catch { }
        }
    }

    private func saveToLibrary(_ data: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        }
    }

    enum CameraError: LocalizedError {
        case noCamera, cannotAddInput, cannotAddOutput
        var errorDescription: String? {
            switch self { case .noCamera: return "No compatible camera was found."; case .cannotAddInput: return "TideCam couldn't connect to the camera."; case .cannotAddOutput: return "TideCam couldn't configure photo capture." }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { Task { @MainActor in self.errorMessage = error.localizedDescription; self.isCapturing = false }; return }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { Task { @MainActor in self.isCapturing = false }; return }
        Task { @MainActor in
            if self.detailFramesRemaining > 0 {
                self.detailFrameData.append(data)
                self.detailFramesRemaining -= 1
                self.detailProgress = 1 - (Double(self.detailFramesRemaining) / 8.0)
                self.captureNextDetailFrame()
            } else {
                self.lastPhoto = image
                self.isCapturing = false
                self.saveToLibrary(data)
            }
        }
    }
}
