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
    @Published var isBursting = false
    @Published var burstCount = 0
    @Published var isRecording = false
    @Published var isPreparingVideo = false
    @Published var isReconfiguringVideo = false
    @Published var videoQuality: VideoQuality = .uhd30
    @Published var actualVideoFormat = "Not configured"
    @Published var videoStabilizationEnabled = true
    @Published var faceEnhancementEnabled = true
    @Published var videoStatus = ""
    @Published var flashMode: FlashMode = .auto
    @Published var lastPhoto: UIImage?
    @Published var errorMessage: String?
    @Published var capabilities = CameraCapabilities()
    @Published var rawEnabled = false
    @Published var iso: Float = 100
    @Published var focus: Float = 0.5
    @Published var zoomFactor: CGFloat = 1
    @Published var minimumZoomFactor: CGFloat = 1
    @Published var maximumZoomFactor: CGFloat = 1
    @Published var nativeZoomFactors: [CGFloat] = [1]
    @Published var zoomEnhanceEnabled = true
    @Published var detailFusionEnabled = true
    @Published var zoomEnhanceStatus = ""
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
    private var configuredVideoMode = false
    private var detailFramesRemaining = 0
    private var detailFramesRequested = 0
    private var detailFrameData: [Data] = []
    private var burstRequested = false
    private let maximumBurstCount = 200

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
                self.configurePhotoOutputForMaximumQuality(device)

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
        // Prefer Apple's virtual multi-camera devices on the rear camera. These let
        // AVFoundation switch between Ultra Wide / Wide / Telephoto while zooming.
        // Falling back to the physical wide camera is important for devices that do
        // not expose a virtual camera.
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInTrueDepthCamera, .builtInWideAngleCamera]

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: position
        ).devices.first
    }

    /// Converts AVFoundation's virtual-camera zoom scale into the familiar Camera
    /// app scale where the physical Wide camera is 1x. Finding the Wide camera's
    /// actual constituent index avoids inventing a fake 0.5x on Wide + Tele devices.
    private func wideReferenceZoomFactor(for device: AVCaptureDevice) -> CGFloat {
        guard device.isVirtualDevice else { return 1 }

        let constituents = device.constituentDevices
        guard let wideIndex = constituents.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }) else {
            return 1
        }
        guard wideIndex > 0 else { return 1 }

        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let switchIndex = wideIndex - 1
        guard switchIndex < switchOvers.count else { return 1 }
        return max(switchOvers[switchIndex], 1)
    }

    /// Returns the native lens buttons for this exact phone. On a typical triple
    /// camera this becomes 0.5x / 1x / 2x, 3x or 5x depending on the telephoto lens.
    /// Digital zoom remains available by pinching, but quick buttons represent real
    /// constituent cameras rather than hard-coded guesses.
    private func nativeDisplayZoomFactors(for device: AVCaptureDevice) -> [CGFloat] {
        let reference = wideReferenceZoomFactor(for: device)
        let minimum = device.minAvailableVideoZoomFactor / reference
        let maximum = min(device.maxAvailableVideoZoomFactor / reference, 20)

        guard device.isVirtualDevice else {
            return [1].filter { $0 >= minimum && $0 <= maximum }
        }

        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let constituents = device.constituentDevices
        var factors: [CGFloat] = []

        for index in constituents.indices {
            let hardwareFactor: CGFloat
            if index == 0 {
                hardwareFactor = 1
            } else if index - 1 < switchOvers.count {
                hardwareFactor = switchOvers[index - 1]
            } else {
                continue
            }

            let displayFactor = hardwareFactor / reference
            if displayFactor >= minimum - 0.01 && displayFactor <= maximum + 0.01 {
                factors.append(displayFactor)
            }
        }

        if !factors.contains(where: { abs($0 - 1) < 0.01 }),
           1 >= minimum, 1 <= maximum {
            factors.append(1)
        }

        let sorted = factors.sorted()
        return sorted.reduce(into: [CGFloat]()) { result, factor in
            if !result.contains(where: { abs($0 - factor) < 0.01 }) {
                result.append(factor)
            }
        }
    }

    private func displayZoomRange(for device: AVCaptureDevice) -> (minimum: CGFloat, maximum: CGFloat, current: CGFloat) {
        let reference = wideReferenceZoomFactor(for: device)
        let minimum = device.minAvailableVideoZoomFactor / reference
        let maximum = min(device.maxAvailableVideoZoomFactor / reference, 20)
        let current = min(max(device.videoZoomFactor / reference, minimum), maximum)
        return (minimum, maximum, current)
    }

    private func largestPhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions? {
        device.activeFormat.supportedMaxPhotoDimensions.max {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }
    }

    /// Configure the expensive parts of the still-photo pipeline once, before the
    /// session starts (and again when the physical camera input changes).
    private func configurePhotoOutputForMaximumQuality(_ device: AVCaptureDevice) {
        photoOutput.maxPhotoQualityPrioritization = .quality

        if let dimensions = largestPhotoDimensions(for: device) {
            photoOutput.maxPhotoDimensions = dimensions
        }

        if photoOutput.isAppleProRAWSupported {
            photoOutput.isAppleProRAWEnabled = true
        }

        if photoOutput.isResponsiveCaptureSupported {
            photoOutput.isResponsiveCaptureEnabled = true
        }

        if photoOutput.isFastCapturePrioritizationSupported {
            photoOutput.isFastCapturePrioritizationEnabled = true
        }

        if photoOutput.isContentAwareDistortionCorrectionSupported {
            photoOutput.isContentAwareDistortionCorrectionEnabled = true
        }
    }

    private func applyMaximumPhotoDimensions(to settings: AVCapturePhotoSettings) {
        let dimensions = photoOutput.maxPhotoDimensions
        guard dimensions.width > 0, dimensions.height > 0 else { return }
        settings.maxPhotoDimensions = dimensions
    }

    private func makeProcessedPhotoSettings() -> AVCapturePhotoSettings {
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            return AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        return AVCapturePhotoSettings()
    }

    private func preferredRawPixelFormatType() -> OSType? {
        let formats = photoOutput.availableRawPhotoPixelFormatTypes
        if photoOutput.isAppleProRAWEnabled,
           let proRAW = formats.first(where: { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }) {
            return proRAW
        }
        return formats.first
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
        let zoomRange = displayZoomRange(for: device)
        let minZoom = zoomRange.minimum
        let maxZoom = zoomRange.maximum
        let currentZoom = zoomRange.current
        let nativeZooms = nativeDisplayZoomFactors(for: device)
        Task { @MainActor in
            self.capabilities = caps
            if !caps.supportsRAW { self.rawEnabled = false }
            self.iso = min(max(currentISO, caps.minimumISO), caps.maximumISO)
            self.focus = min(max(currentFocus, 0), 1)
            self.minimumZoomFactor = minZoom
            self.maximumZoomFactor = maxZoom
            self.zoomFactor = currentZoom
            self.nativeZoomFactors = nativeZooms
        }
    }

    func setZoom(_ value: CGFloat, smoothly: Bool = false) {
        guard value.isFinite else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            let reference = self.wideReferenceZoomFactor(for: device)
            let minimum = device.minAvailableVideoZoomFactor / reference
            let maximum = min(device.maxAvailableVideoZoomFactor / reference, 20)
            let clamped = min(max(value, minimum), maximum)
            let hardwareZoom = min(
                max(clamped * reference, device.minAvailableVideoZoomFactor),
                device.maxAvailableVideoZoomFactor
            )
            do {
                try device.lockForConfiguration()
                if smoothly {
                    device.ramp(toVideoZoomFactor: hardwareZoom, withRate: 8)
                } else {
                    device.cancelVideoZoomRamp()
                    device.videoZoomFactor = hardwareZoom
                }
                device.unlockForConfiguration()
                Task { @MainActor in
                    self.minimumZoomFactor = minimum
                    self.maximumZoomFactor = maximum
                    self.zoomFactor = clamped
                }
            } catch {
                Task { @MainActor in
                    self.errorMessage = "Zoom control failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func capturePhoto() {
        guard isConfigured, !isCapturing, !isRecording, !isPreparingVideo else { return }
        isCapturing = true

        let isRawCapture: Bool
        let settings: AVCapturePhotoSettings
        if rawEnabled, let rawType = preferredRawPixelFormatType() {
            isRawCapture = true
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawType)
        } else {
            isRawCapture = false
            settings = makeProcessedPhotoSettings()
        }

        applyMaximumPhotoDimensions(to: settings)
        settings.photoQualityPrioritization = .quality

        if !isRawCapture {
            if photoOutput.isVirtualDeviceFusionSupported {
                settings.isAutoVirtualDeviceFusionEnabled = true
            }
            if let device = videoInput?.device, device.hasFlash {
                settings.flashMode = flashMode.avMode
            }
            if photoOutput.isAutoRedEyeReductionSupported {
                settings.isAutoRedEyeReductionEnabled = true
            }
            if photoOutput.isContentAwareDistortionCorrectionSupported {
                settings.isAutoContentAwareDistortionCorrectionEnabled = true
            }
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// Hold-to-shoot burst. Burst deliberately captures processed HEIF/JPEG frames
    /// with speed prioritization so the camera can keep firing instead of waiting
    /// for the heavier single-shot quality pipeline between every frame.
    /// Digital-zoom enhancement is optional and never modifies the source.
    /// The original remains in TideLibrary; the enhanced copy goes to Photos.
    private func savePhotoWithOptionalEnhancement(_ data: Data, preview: UIImage) {
        let capturedZoom = zoomFactor
        guard zoomEnhanceEnabled && capturedZoom >= 1.5 else {
            lastPhoto = preview
            isCapturing = false
            saveToLibrary(data)
            return
        }

        zoomEnhanceStatus = "Enhancing zoom"
        processingQueue.async { [weak self] in
            let enhanced = ZoomEnhancer().enhance(data, zoomFactor: capturedZoom)
            let keepOriginal = enhanced != nil && (try? TideCamLibraryStorage.save(data)) != nil
            let finalData = keepOriginal ? enhanced! : data
            let finalPreview = keepOriginal ? (UIImage(data: finalData) ?? preview) : preview

            Task { @MainActor in
                guard let self else { return }
                self.lastPhoto = finalPreview
                self.isCapturing = false
                self.zoomEnhanceStatus = keepOriginal ? "Enhanced · original in TideLibrary" : ""
                self.saveToLibrary(finalData)
                if keepOriginal { TideCamLibraryStore.shared.refresh() }
            }
        }
    }

    func beginBurst() {
        guard isConfigured, !isCapturing, !isRecording, !isPreparingVideo else { return }
        burstRequested = true
        burstCount = 0
        isBursting = true
        isCapturing = true
        captureNextBurstFrame()
    }

    func endBurst() {
        burstRequested = false
    }

    private func captureNextBurstFrame() {
        guard burstRequested, burstCount < maximumBurstCount else {
            burstRequested = false
            isBursting = false
            isCapturing = false
            return
        }

        let settings = makeProcessedPhotoSettings()
        applyMaximumPhotoDimensions(to: settings)
        settings.photoQualityPrioritization = .speed
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
    }

    private func lockForDetailCapture() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let device = self.videoInput?.device {
                do {
                    try device.lockForConfiguration()
                    if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                    if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                    if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
                    device.unlockForConfiguration()
                } catch {
                    // Still allow a capture if a device can't lock these controls.
                }
            }
            Task { @MainActor in
                self.detailStatus = "Collecting frames"
                self.captureNextDetailFrame()
            }
        }
    }

    private func captureNextDetailFrame() {
        guard detailFramesRemaining > 0 else { finishDetailBurst(); return }
        let settings = makeProcessedPhotoSettings()
        applyMaximumPhotoDimensions(to: settings)
        settings.photoQualityPrioritization = .balanced
        if photoOutput.isVirtualDeviceFusionSupported {
            settings.isAutoVirtualDeviceFusionEnabled = true
        }
        if photoOutput.isContentAwareDistortionCorrectionSupported {
            settings.isAutoContentAwareDistortionCorrectionEnabled = true
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func finishDetailBurst() {
        let frames = detailFrameData
        let enhance = zoomEnhanceEnabled && zoomFactor >= 1.5
        let fuse = detailFusionEnabled
        let capturedZoom = zoomFactor
        detailStatus = "Analysing sharpness"
        processingQueue.async { [weak self] in
            // Rank encoded images instead of retaining many decoded UIImages.
            let ranked = DetailProcessor().rankedFrames(from: frames)
            guard let best = ranked.first else {
                Task { @MainActor in
                    guard let self else { return }
                    self.detailStatus = "Capture failed"
                    self.detailFrameData.removeAll()
                    self.detailProgress = 1
                    self.isCapturing = false
                    self.restoreAutomaticCamera()
                }
                return
            }

            // Reject obviously softer or differently exposed images before
            // alignment. Vision and the per-pixel mask handle smaller motion.
            let alternatives = ranked.dropFirst().filter {
                $0.sharpness >= best.sharpness * 0.65 &&
                abs($0.brightness - best.brightness) <= 0.07
            }.map(\.data)
            let fusion = fuse
                ? MultiFrameFusion().fuse(reference: best.data, alternatives: alternatives)
                : nil

            let fusedData = fusion?.data ?? best.data
            let zoomData = enhance
                ? ZoomEnhancer().enhance(fusedData, zoomFactor: capturedZoom)
                : nil
            let proposedData = zoomData ?? fusion?.data

            // Never save a derivative as the only copy. If the original can't
            // be preserved, use the best source photo without enhancement.
            let originalSaved = proposedData != nil &&
                (try? TideCamLibraryStorage.save(best.data)) != nil
            let savedData = originalSaved ? (proposedData ?? best.data) : best.data
            let preview = UIImage(data: savedData)
            let framesFused = originalSaved ? (fusion?.frameCount ?? 1) : 1
            let usedZoomEnhance = originalSaved && zoomData != nil

            Task { @MainActor in
                guard let self else { return }
                self.lastPhoto = preview
                self.saveToLibrary(savedData)
                if framesFused > 1 {
                    self.detailStatus = usedZoomEnhance
                        ? "Fused \(framesFused) frames + zoom enhanced"
                        : "Fused \(framesFused) frames"
                } else {
                    self.detailStatus = usedZoomEnhance ? "Zoom enhanced" : "Best frame saved"
                }
                if originalSaved { TideCamLibraryStore.shared.refresh() }
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

    /// Reconfigure capture only while idle, and report the ACTUAL format chosen
    /// by AVFoundation rather than claiming 4K60 on an unsupported phone.
    func setVideoMode(_ enabled: Bool, quality: VideoQuality? = nil) {
        guard isConfigured, !isRecording, !isCapturing, !isPreparingVideo, !isReconfiguringVideo else { return }
        if let quality { videoQuality = quality }
        let requested = videoQuality
        isReconfiguringVideo = true
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else {
                Task { @MainActor in self?.isReconfiguringVideo = false }
                return
            }
            self.session.beginConfiguration()
            if enabled {
                self.configureRecordingFormat(device, requested: requested)
            } else if self.session.canSetSessionPreset(.photo) {
                self.session.sessionPreset = .photo
                self.configurePhotoOutputForMaximumQuality(device)
            }
            self.session.commitConfiguration()
            self.configuredVideoMode = enabled
            if enabled { self.configureRecordingConnection() }
            self.publishCapabilities(for: device)
            Task { @MainActor in
                self.isReconfiguringVideo = false
                self.actualVideoFormat = enabled ? self.recordingFormatLabel(for: device) : "Photo mode"
            }
        }
    }

    /// Caller must own a session configuration transaction.
    /// Prefer an exact format with the requested frame rate, otherwise fall
    /// back safely to a preset and display the resulting camera format.
    private func configureRecordingFormat(_ device: AVCaptureDevice, requested: VideoQuality) {
        let choices: [VideoQuality] = {
            switch requested {
            case .uhd60: return [.uhd60, .uhd30, .fhd60, .fhd30]
            case .uhd30: return [.uhd30, .fhd30]
            case .fhd60: return [.fhd60, .fhd30]
            case .fhd30: return [.fhd30]
            }
        }()

        for choice in choices {
            let formats = device.formats.filter { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dimensions.width == choice.width &&
                    dimensions.height == choice.height &&
                    format.videoSupportedFrameRateRanges.contains {
                        $0.minFrameRate <= Double(choice.fps) &&
                        $0.maxFrameRate >= Double(choice.fps)
                    }
            }
            guard let format = formats.first else { continue }
            do {
                try device.lockForConfiguration()
                self.session.sessionPreset = .inputPriority
                device.activeFormat = format
                let duration = CMTime(value: 1, timescale: choice.fps)
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                device.unlockForConfiguration()
                return
            } catch {
                continue
            }
        }

        // On cameras exposing no exact format (e.g. some virtual cameras),
        // prefer the highest supported session preset rather than failing.
        for preset in [AVCaptureSession.Preset.hd4K3840x2160, .hd1920x1080, .high] {
            if session.canSetSessionPreset(preset) {
                session.sessionPreset = preset
                return
            }
        }
    }

    private func recordingFormatLabel(for device: AVCaptureDevice) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let fpsTime = device.activeVideoMinFrameDuration
        let fps: Int
        if fpsTime.isValid && CMTimeGetSeconds(fpsTime) > 0 {
            fps = Int((1 / CMTimeGetSeconds(fpsTime)).rounded())
        } else {
            fps = 0
        }
        let size = dimensions.width >= 3800 && dimensions.height >= 2100
            ? "4K" : "\(dimensions.width)×\(dimensions.height)"
        return fps > 0 ? "\(size) · \(fps) fps" : size
    }

    private func configureRecordingConnection() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = videoStabilizationEnabled ? .auto : .off
        }
        // HEVC is supported in hardware on modern iPhones and provides better
        // compression at typical quality levels. Fall back to the default codec.
        if movieOutput.availableVideoCodecTypes.contains(.hevc),
           movieOutput.supportedOutputSettingsKeys(for: connection).contains(AVVideoCodecKey) {
            movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
        }
    }

    func setVideoStabilization(_ enabled: Bool) {
        guard !isRecording, !isPreparingVideo else { return }
        videoStabilizationEnabled = enabled
        sessionQueue.async { [weak self] in self?.configureRecordingConnection() }
    }

    func toggleVideoRecording() {
        if isRecording {
            sessionQueue.async { [weak self] in self?.movieOutput.stopRecording() }
            return
        }
        guard isConfigured, capabilities.supportsVideo, !isCapturing,
              !isPreparingVideo, !isReconfiguringVideo else { return }
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
            guard self.session.outputs.contains(where: { $0 === self.movieOutput }),
                  let device = self.videoInput?.device else {
                Task { @MainActor in
                    self.isPreparingVideo = false
                    self.errorMessage = "Video recording is not available on this camera."
                }
                return
            }

            // If the user tapped Record before selecting VIDEO, configure
            // video quality on this same serial queue before recording.
            if !self.configuredVideoMode {
                self.session.beginConfiguration()
                self.configureRecordingFormat(device, requested: self.videoQuality)
                self.session.commitConfiguration()
                self.configuredVideoMode = true
                Task { @MainActor in self.actualVideoFormat = self.recordingFormatLabel(for: device) }
            }

            if includeAudio, self.audioInput == nil,
               let microphone = AVCaptureDevice.default(for: .audio) {
                do {
                    let input = try AVCaptureDeviceInput(device: microphone)
                    self.session.beginConfiguration()
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.audioInput = input
                    }
                    self.session.commitConfiguration()
                } catch {
                    Task { @MainActor in self.videoStatus = "Microphone unavailable" }
                }
            }
            self.configureRecordingConnection()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "TideCam-\(UUID().uuidString).mov"
            )
            if let connection = self.movieOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            // isRecording changes only from the delegate's real start callback.
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
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
                self.configurePhotoOutputForMaximumQuality(device)
                self.prepareAutomaticCamera(device)
                if self.configuredVideoMode {
                    self.configureRecordingFormat(device, requested: self.videoQuality)
                } else if self.session.canSetSessionPreset(.photo) {
                    self.session.sessionPreset = .photo
                }
                self.publishCapabilities(for: device)
            } else {
                self.session.addInput(currentInput)
                self.videoInput = currentInput
            }
            self.session.commitConfiguration()
            if self.configuredVideoMode { self.configureRecordingConnection() }
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
        Task {
            let granted = await requestPhotoLibraryAddAccess()
            guard granted else {
                self.errorMessage = "Allow TideCam to add photos in Settings so captures appear in TideLibrary."
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    if let preferredExtension {
                        options.originalFilename = "TideCam-\(UUID().uuidString).\(preferredExtension)"
                    }
                    request.addResource(with: .photo, data: data, options: options)
                }
            } catch {
                self.errorMessage = "Photo library save failed: \(error.localizedDescription)"
            }
        }
    }

    private func saveVideoToLibrary(_ url: URL) {
        Task {
            let granted = await requestPhotoLibraryAddAccess()
            guard granted else {
                self.errorMessage = "Allow TideCam to add photos in Settings so videos appear in TideLibrary."
                try? FileManager.default.removeItem(at: url)
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    options.originalFilename = "TideCam-\(UUID().uuidString).mov"
                    request.addResource(with: .video, fileURL: url, options: options)
                }
            } catch {
                self.errorMessage = "Photo library video save failed: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func requestPhotoLibraryAddAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
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
            Task { @MainActor in
                self.errorMessage = error.localizedDescription
                self.burstRequested = false
                self.isBursting = false
                self.isCapturing = false
            }
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
            } else if self.isBursting {
                self.lastPhoto = image
                self.burstCount += 1
                self.saveToLibrary(data)

                if self.burstRequested && self.burstCount < self.maximumBurstCount {
                    self.captureNextBurstFrame()
                } else {
                    self.burstRequested = false
                    self.isBursting = false
                    self.isCapturing = false
                }
            } else {
                self.savePhotoWithOptionalEnhancement(data, preview: image)
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