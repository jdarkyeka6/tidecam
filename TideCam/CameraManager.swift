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
    @Published var isRecording = false
    @Published var isPreparingVideo = false
    @Published var flashMode: FlashMode = .auto
    @Published var lastPhoto: UIImage?
    @Published var errorMessage: String?
    @Published var capabilities = CameraCapabilities()
    @Published var rawEnabled = false
    @Published var iso: Float = 100
    @Published var focus: Float = 0.5
    @Published var detailProgress: Double = 0
    @Published var detailStatus = "Ready"
    @Published var detailFrameCount = 12
    @Published var activeRecipe: CameraRecipe = .builtIns[0]

    private let sessionQueue = DispatchQueue(label: "com.tidecam.session")
    private let processingQueue = DispatchQueue(label: "com.tidecam.detail", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var detailFramesRemaining = 0
    private var detailFramesRequested = 0
    private var detailFrameData: [Data] = []

    override init() { super.init(); Task { await requestPermissionAndConfigure() } }

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

                var supportsVideo = false
                if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                    supportsVideo = true
                }

                self.session.commitConfiguration()
                self.prepareAutomaticCamera(device)
                self.session.startRunning()
                self.publishCapabilities(for: device, supportsVideo: supportsVideo)
                Task { @MainActor in self.isConfigured = true }
            } catch {
                self.session.commitConfiguration()
                Task { @MainActor in self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let physicalWide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return physicalWide
        }
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera]
            : [.builtInTrueDepthCamera]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position).devices.first
    }

    private func prepareAutomaticCamera(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            device.unlockForConfiguration()
        } catch { }
    }

    private func publishCapabilities(for device: AVCaptureDevice, supportsVideo: Bool? = nil) {
        let caps = CameraCapabilities(
            supportsRAW: !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty,
            supportsManualFocus: device.isLockingFocusWithCustomLensPositionSupported,
            supportsCustomExposure: device.isExposureModeSupported(.custom),
            supportsTorch: device.hasTorch,
            supportsDepth: !device.activeFormat.supportedDepthDataFormats.isEmpty,
            supportsVideo: supportsVideo ?? session.outputs.contains { $0 === movieOutput },
            minimumISO: device.activeFormat.minISO,
            maximumISO: device.activeFormat.maxISO
        )
        let currentFocus = device.lensPosition
        let currentISO = device.iso
        Task { @MainActor in
            self.capabilities = caps
            if !caps.supportsRAW { self.rawEnabled = false }
            self.iso = min(max(currentISO, caps.minimumISO), caps.maximumISO)
            self.focus = min(max(currentFocus, 0), 1)
        }
    }

    func capturePhoto() {
        guard isConfigured, !isCapturing, !isRecording, !isPreparingVideo else { return }
        isCapturing = true

        let isRawCapture: Bool
        let settings: AVCapturePhotoSettings
        if rawEnabled, let rawType = photoOutput.availableRawPhotoPixelFormatTypes.first {
            isRawCapture = true
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawType)
        } else {
            isRawCapture = false
            settings = AVCapturePhotoSettings()
        }

        if !isRawCapture, let device = videoInput?.device, device.hasFlash {
            settings.flashMode = flashMode.avMode
        }
        if !isRawCapture {
            settings.photoQualityPrioritization = .quality
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func captureDetailBurst(frameCount: Int? = nil) {
        guard isConfigured, !isCapturing, !isRecording, !isPreparingVideo else { return }
        let count = min(max(frameCount ?? detailFrameCount, 4), 30)
        detailFramesRequested = count
        detailFramesRemaining = count
        detailFrameData.removeAll(keepingCapacity: true)
        detailProgress = 0
        detailStatus = "Locking camera"
        isCapturing = true
        lockForDetailCapture()
        captureNextDetailFrame()
    }

    private func lockForDetailCapture() {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
                device.unlockForConfiguration()
                Task { @MainActor in self?.detailStatus = "Collecting frames" }
            } catch { }
        }
    }

    private func captureNextDetailFrame() {
        guard detailFramesRemaining > 0 else { finishDetailBurst(); return }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .speed
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func finishDetailBurst() {
        let frames = detailFrameData
        detailStatus = "Analysing sharpness"
        processingQueue.async { [weak self] in
            let best = DetailProcessor().bestCandidate(from: frames)
            Task { @MainActor in
                guard let self else { return }
                if let best {
                    self.lastPhoto = best.image
                    self.saveToLibrary(best.data)
                    self.detailStatus = "Best frame saved"
                } else { self.detailStatus = "Capture failed" }
                self.detailFrameData.removeAll()
                self.detailProgress = 1
                self.isCapturing = false
                self.restoreAutomaticCamera()
            }
        }
    }

    private func restoreAutomaticCamera() {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            self?.prepareAutomaticCamera(device)
        }
    }

    func applyRecipe(_ recipe: CameraRecipe) {
        activeRecipe = recipe
        rawEnabled = recipe.rawEnabled && capabilities.supportsRAW
        detailFrameCount = min(max(recipe.detailFrames, 4), 30)
        if let value = recipe.iso, capabilities.supportsCustomExposure { setISO(value) }
        if let value = recipe.focus, capabilities.supportsManualFocus { setFocus(value) }
    }

    func setISO(_ value: Float) {
        guard value.isFinite else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device, device.isExposureModeSupported(.custom) else { return }
            do {
                try device.lockForConfiguration()
                let clamped = min(max(value, device.activeFormat.minISO), device.activeFormat.maxISO)
                let duration = device.exposureDuration
                device.setExposureModeCustom(duration: duration, iso: clamped, completionHandler: nil)
                device.unlockForConfiguration()
                Task { @MainActor in self.iso = clamped }
            } catch {
                Task { @MainActor in self.errorMessage = "ISO control failed: \(error.localizedDescription)" }
            }
        }
    }

    func setFocus(_ value: Float) {
        guard value.isFinite else { return }
        let requested = min(max(value, 0), 1)
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device,
                  device.isLockingFocusWithCustomLensPositionSupported else { return }
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: requested) { _ in
                    let actual = device.lensPosition
                    Task { @MainActor in self.focus = actual }
                }
                device.unlockForConfiguration()
                Task { @MainActor in self.focus = requested }
            } catch {
                Task { @MainActor in self.errorMessage = "Focus control failed: \(error.localizedDescription)" }
            }
        }
    }

    func toggleVideoRecording() {
        if isRecording { movieOutput.stopRecording(); return }
        guard isConfigured, capabilities.supportsVideo, !isCapturing, !isPreparingVideo else { return }
        isPreparingVideo = true
        Task { beginVideoRecording(includeAudio: await requestMicrophoneAccessIfNeeded()) }
    }

    private func requestMicrophoneAccessIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private func beginVideoRecording(includeAudio: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.outputs.contains(where: { $0 === self.movieOutput }) else {
                Task { @MainActor in self.isPreparingVideo = false; self.errorMessage = "Video recording is not available on this camera." }
                return
            }
            if includeAudio, self.audioInput == nil, let microphone = AVCaptureDevice.default(for: .audio) {
                do {
                    let input = try AVCaptureDeviceInput(device: microphone)
                    self.session.beginConfiguration()
                    if self.session.canAddInput(input) { self.session.addInput(input); self.audioInput = input }
                    self.session.commitConfiguration()
                } catch { }
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("TideCam-\(UUID().uuidString).mov")
            if let connection = self.movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            Task { @MainActor in self.isPreparingVideo = false; self.isRecording = true }
        }
    }

    func cycleFlash() {
        switch flashMode { case .off: flashMode = .auto; case .auto: flashMode = .on; case .on: flashMode = .off }
    }

    func switchCamera() {
        guard !isRecording, !isPreparingVideo, !isCapturing else { return }
        sessionQueue.async { [weak self] in
            guard let self, let currentInput = self.videoInput else { return }
            let newPosition: AVCaptureDevice.Position = self.position == .back ? .front : .back
            guard let device = self.bestDevice(for: newPosition), let newInput = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(currentInput)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
                self.position = newPosition
                self.prepareAutomaticCamera(device)
                self.publishCapabilities(for: device)
            } else {
                self.session.addInput(currentInput)
                self.videoInput = currentInput
            }
            self.session.commitConfiguration()
        }
    }

    func focus(at devicePoint: CGPoint) {
        guard !isRecording, !isPreparingVideo else { return }
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }

    private func saveToLibrary(_ data: Data, preferredExtension: String? = nil) {
        do {
            _ = try TideCamLibraryStorage.save(data, preferredExtension: preferredExtension)
            TideCamLibraryStore.shared.refresh()
        } catch {
            errorMessage = "TideCam library save failed: \(error.localizedDescription)"
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        }
    }

    private func saveVideoToLibrary(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else { try? FileManager.default.removeItem(at: url); return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            } completionHandler: { success, error in
                try? FileManager.default.removeItem(at: url)
                if !success, let error { Task { @MainActor in self?.errorMessage = error.localizedDescription } }
            }
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
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.isCapturing = false }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor in self.isCapturing = false; self.errorMessage = "TideCam couldn't create the captured photo." }
            return
        }

        Task { @MainActor in
            if photo.isRawPhoto {
                self.isCapturing = false
                self.saveToLibrary(data, preferredExtension: "dng")
                return
            }

            guard let image = UIImage(data: data) else {
                self.isCapturing = false
                self.errorMessage = "TideCam couldn't decode the captured photo."
                return
            }

            if self.detailFramesRemaining > 0 {
                self.detailFrameData.append(data)
                self.detailFramesRemaining -= 1
                self.detailProgress = 1 - (Double(self.detailFramesRemaining) / Double(max(self.detailFramesRequested, 1)))
                self.captureNextDetailFrame()
            } else {
                self.lastPhoto = image
                self.isCapturing = false
                self.saveToLibrary(data)
            }
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Task { @MainActor in self.isPreparingVideo = false; self.isRecording = true }
    }
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.isPreparingVideo = false; self.isRecording = false
            if let error { try? FileManager.default.removeItem(at: outputFileURL); self.errorMessage = error.localizedDescription }
            else { self.saveVideoToLibrary(outputFileURL) }
        }
    }
}