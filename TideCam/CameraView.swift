import SwiftUI

struct CameraView: View {
    @StateObject private var camera = CameraManager()
    @State private var selectedMode: CameraMode = .photo
    @State private var showRecipes = false
    @State private var showLibrary = false
    @State private var burstGestureTriggered = false
    @State private var showAdvancedVideoControls = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.isAuthorized {
                CameraPreview(
                    session: camera.session,
                    onFocus: camera.focus,
                    onZoom: { camera.setZoom($0) },
                    currentZoom: camera.zoomFactor
                )
                .ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.58), .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
                controls
            } else { permissionView }
        }
        .sheet(isPresented: $showRecipes) { recipeSheet.presentationDetents([.medium]) }
        .fullScreenCover(isPresented: $showLibrary) { TideCamLibraryView() }
        .alert("TideCam", isPresented: Binding(get: { camera.errorMessage != nil }, set: { if !$0 { camera.errorMessage = nil } })) {
            Button("OK", role: .cancel) { camera.errorMessage = nil }
        } message: {
            Text(camera.errorMessage ?? "Unknown camera error")
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if selectedMode == .video {
                        camera.toggleVideoTorch()
                    } else {
                        camera.cycleFlash()
                    }
                } label: {
                    Image(systemName: selectedMode == .video
                          ? (camera.videoTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                          : camera.flashMode.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(selectedMode == .video && !camera.capabilities.supportsTorch)
                Spacer()
                VStack(spacing: 1) {
                    Text("TIDECAM").font(.system(size: 15, weight: .bold, design: .rounded)).tracking(2.2)
                    if camera.isRecording {
                        Text("● REC").font(.system(size: 8, weight: .bold)).foregroundStyle(.red)
                    } else {
                        Text(camera.activeRecipe.name.uppercased()).font(.system(size: 8, weight: .bold)).foregroundStyle(.yellow)
                    }
                }
                Spacer()
                Button { showRecipes = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .bold)).frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                }
                .disabled(camera.isRecording || camera.isPreparingVideo)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer()

            if camera.nativeZoomFactors.count > 1 {
                HStack(spacing: 10) {
                    ForEach(zoomPresets, id: \.self) { factor in
                        Button {
                            camera.setZoom(factor, smoothly: true)
                        } label: {
                            Text(zoomLabel(factor))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(abs(camera.zoomFactor - factor) < 0.08 ? .black : .white)
                                .frame(width: 44, height: 34)
                                .background(
                                    abs(camera.zoomFactor - factor) < 0.08 ? Color.yellow : Color.black.opacity(0.48),
                                    in: Capsule()
                                )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 12)
            }

            if selectedMode == .photo || selectedMode == .detail ||
                selectedMode == .pro || selectedMode == .video {
                zoomControl
            }

            if selectedMode == .photo || selectedMode == .detail {
                zoomEnhanceControl
                faceEnhanceControl
            }

            if selectedMode == .pro { proPanel.transition(.move(edge: .bottom).combined(with: .opacity)) }
            if selectedMode == .detail { detailPanel.transition(.move(edge: .bottom).combined(with: .opacity)) }
            if selectedMode == .video { videoPanel.transition(.move(edge: .bottom).combined(with: .opacity)) }

            VStack(spacing: 22) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 26) {
                        ForEach(CameraMode.allCases) { mode in
                            Button {
                                withAnimation(.snappy) { selectedMode = mode }
                                camera.setVideoMode(mode == .video)
                            } label: {
                                VStack(spacing: 3) {
                                    Text(mode.rawValue).font(.system(size: 13, weight: selectedMode == mode ? .bold : .medium))
                                    if !mode.isImplemented { Text("SOON").font(.system(size: 7, weight: .bold)) }
                                }
                                .foregroundStyle(selectedMode == mode ? .yellow : .white.opacity(mode.isImplemented ? 0.72 : 0.38))
                            }
                            .disabled(camera.isRecording || camera.isPreparingVideo || camera.isReconfiguringVideo || camera.isCapturing)
                        }
                    }
                    .padding(.horizontal, 30)
                }

                HStack {
                    Button { showLibrary = true } label: {
                        Group {
                            if let image = camera.lastPhoto {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Image(systemName: "photo.on.rectangle.angled").font(.title3).foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .frame(width: 54, height: 54)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.black.opacity(0.55), in: Circle())
                                .offset(x: 3, y: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.isRecording || camera.isPreparingVideo || camera.isCapturing)

                    Spacer()

                    Button {
                        guard !burstGestureTriggered else { return }
                        shutter()
                    } label: {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                            shutterFill
                        }
                    }
                    .onLongPressGesture(
                        minimumDuration: 0.28,
                        maximumDistance: 50,
                        pressing: { pressing in
                            if !pressing, burstGestureTriggered {
                                camera.endBurst()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    burstGestureTriggered = false
                                }
                            }
                        },
                        perform: {
                            guard burstEligible, !shutterDisabled else { return }
                            burstGestureTriggered = true
                            camera.beginBurst()
                        }
                    )
                    .disabled(shutterDisabled)

                    Spacer()

                    Button(action: camera.switchCamera) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera.fill").font(.system(size: 23, weight: .medium)).foregroundStyle(.white).frame(width: 54, height: 54).background(.ultraThinMaterial, in: Circle())
                    }
                    .disabled(camera.isRecording || camera.isPreparingVideo || camera.isCapturing)
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var shutterFill: some View {
        if selectedMode == .video {
            if camera.isRecording {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.red).frame(width: 32, height: 32)
            } else {
                Circle().fill(.red).frame(width: camera.isPreparingVideo ? 58 : 66, height: camera.isPreparingVideo ? 58 : 66)
            }
        } else if camera.isBursting {
            ZStack {
                Circle().fill(.yellow).frame(width: 58, height: 58)
                Text("\(camera.burstCount)")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .monospacedDigit()
            }
        } else {
            Circle().fill(selectedMode == .detail ? .yellow : .white).frame(width: camera.isCapturing ? 58 : 66, height: camera.isCapturing ? 58 : 66)
        }
    }

    private var burstEligible: Bool {
        selectedMode == .photo || selectedMode == .pro
    }

    private var shutterDisabled: Bool {
        if selectedMode == .video {
            return !camera.capabilities.supportsVideo || camera.isPreparingVideo || camera.isReconfiguringVideo || camera.isStoppingVideo || camera.isCapturing
        }
        return !selectedMode.isImplemented || (camera.isCapturing && !camera.isBursting) || camera.isRecording || camera.isPreparingVideo
    }

    private var zoomControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.magnifyingglass")
                .font(.caption.bold())
            Text(String(format: "%.1f×", camera.zoomFactor))
                .font(.caption.monospacedDigit().bold())
                .frame(width: 45, alignment: .leading)

            Slider(
                value: Binding(
                    get: { Double(camera.zoomFactor) },
                    set: { camera.setZoom(CGFloat($0)) }
                ),
                in: Double(camera.minimumZoomFactor)...Double(max(camera.maximumZoomFactor, camera.minimumZoomFactor + 0.01))
            )
            .tint(.yellow)

            Text(String(format: "%.0f×", camera.maximumZoomFactor))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 18)
        .padding(.bottom, 9)
        .disabled(camera.isCapturing)
    }

    private var zoomEnhanceControl: some View {
        Button {
            camera.zoomEnhanceEnabled.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: camera.zoomEnhanceEnabled ? "sparkles" : "sparkles.slash")
                Text("ZOOM ENHANCE")
                    .tracking(0.8)
                Text(camera.zoomEnhanceEnabled ? "ON" : "OFF")
                    .foregroundStyle(camera.zoomEnhanceEnabled ? .yellow : .white.opacity(0.6))
                Spacer()
                if !camera.zoomEnhanceStatus.isEmpty {
                    Text(camera.zoomEnhanceStatus)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                } else {
                    Text("1.5×+ digital cleanup")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .disabled(camera.isCapturing)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var faceEnhanceControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "face.smiling.inverse")
            Text("FACE DETAIL")
                .font(.caption.bold())
            Spacer()
            Text("Vision AI detection")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
            Toggle("Face Detail", isOn: $camera.faceEnhancementEnabled)
                .labelsHidden()
                .tint(.yellow)
                .disabled(camera.isCapturing)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var detailPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "sparkles.rectangle.stack.fill")
                Text(camera.isCapturing ? camera.detailStatus.uppercased() : "MULTI-FRAME DETAIL").font(.caption.bold()).tracking(1)
                Spacer()
                Text("\(camera.detailFrameCount)×").font(.caption.monospacedDigit().bold())
            }
            if camera.isCapturing {
                ProgressView(value: camera.detailProgress).tint(.yellow)
            } else {
                Slider(value: Binding(get: { Double(camera.detailFrameCount) }, set: { camera.detailFrameCount = Int($0) }), in: 4...30, step: 2).tint(.yellow)
            }
            HStack {
                Image(systemName: "square.stack.3d.up")
                Text("SMART FUSION")
                    .font(.caption.bold())
                Spacer()
                Toggle("Smart Fusion", isOn: $camera.detailFusionEnabled)
                    .labelsHidden()
                    .tint(.yellow)
                    .disabled(camera.isCapturing)
            }

            Text(camera.isCapturing
                 ? "Hold steady. TideCam is collecting frames for alignment."
                 : camera.detailFusionEnabled
                    ? "Aligns compatible frames and combines stable areas. Motion falls back to the sharpest capture."
                    : "Selects the sharpest original frame without fusion.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var videoPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: camera.isRecording ? "record.circle.fill" : "video.fill")
                    .foregroundStyle(camera.isRecording ? .red : .white)
                Text(camera.isRecording ? "RECORDING" :
                    camera.isStoppingVideo ? "SAVING" :
                    camera.isReconfiguringVideo ? "CONFIGURING" : "VIDEO PRO")
                    .font(.caption.bold())
                    .tracking(0.8)
                Spacer()
                if camera.isRecording, let started = camera.recordingStartedAt {
                    TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                        Text(recordingTime(timeline.date.timeIntervalSince(started)))
                            .foregroundStyle(.red)
                            .font(.caption.monospacedDigit().bold())
                    }
                }
                Text(camera.actualVideoFormat)
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(.yellow)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VideoQuality.allCases) { quality in
                        Button {
                            camera.setVideoMode(true, quality: quality)
                        } label: {
                            Text(quality.rawValue)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(
                                    camera.videoQuality == quality
                                        ? Color.yellow : Color.white.opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(camera.videoQuality == quality ? .black : .white)
                        }
                        .disabled(camera.isRecording || camera.isPreparingVideo ||
                                  camera.isReconfiguringVideo || camera.isStoppingVideo)
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "figure.walk.motion")
                Text(camera.actualStabilizationStatus)
                    .font(.caption2)
                Spacer()
                Button {
                    withAnimation(.snappy) { showAdvancedVideoControls.toggle() }
                } label: {
                    Label(showAdvancedVideoControls ? "Less" : "More controls",
                          systemImage: "slider.horizontal.3")
                        .font(.caption2.bold())
                }
                .buttonStyle(.plain)
            }

            if showAdvancedVideoControls {
                videoAdvancedControls
            }

            if !camera.videoStatus.isEmpty {
                Text(camera.videoStatus)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var videoAdvancedControls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Stabilisation").font(.caption2)
                Spacer()
                Toggle("Stabilisation", isOn: Binding(
                    get: { camera.videoStabilizationEnabled },
                    set: { camera.setVideoStabilization($0) }
                ))
                .labelsHidden()
                .tint(.yellow)
            }
            HStack {
                Text("Microphone").font(.caption2)
                Spacer()
                Toggle("Microphone", isOn: Binding(
                    get: { camera.videoAudioEnabled },
                    set: { camera.setVideoAudio($0) }
                ))
                .labelsHidden()
                .tint(.yellow)
            }
            HStack {
                Text("HDR video").font(.caption2)
                Spacer()
                Text(camera.actualHDRStatus)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                Toggle("HDR video", isOn: Binding(
                    get: { camera.videoHDREnabled },
                    set: { camera.setVideoHDR($0) }
                ))
                .labelsHidden()
                .tint(.yellow)
            }
            HStack(spacing: 10) {
                Text("EV").font(.caption2.bold())
                Slider(
                    value: Binding(
                        get: { Double(camera.videoExposureBias) },
                        set: { camera.setVideoExposureBias(Float($0)) }
                    ),
                    in: -2...2
                )
                .tint(.yellow)
                Text(String(format: "%+.1f", camera.videoExposureBias))
                    .font(.caption2.monospacedDigit())
                    .frame(width: 38)
            }
        }
        .disabled(camera.isRecording || camera.isPreparingVideo ||
                  camera.isReconfiguringVideo || camera.isStoppingVideo)
    }

    private func recordingTime(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed))
        return String(format: "%02d:%02d:%02d",
                      seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private var proPanel: some View {
        VStack(spacing: 13) {
            HStack {
                Text("ISO").font(.caption.bold()).frame(width: 44, alignment: .leading)
                Slider(value: Binding(get: { Double(camera.iso) }, set: { camera.setISO(Float($0)) }), in: Double(max(camera.capabilities.minimumISO, 20))...Double(max(camera.capabilities.maximumISO, 100)))
                Text("\(Int(camera.iso))").font(.caption.monospacedDigit()).frame(width: 48)
            }
            .disabled(!camera.capabilities.supportsCustomExposure)
            .opacity(camera.capabilities.supportsCustomExposure ? 1 : 0.35)

            HStack {
                Text("FOCUS").font(.caption.bold()).frame(width: 44, alignment: .leading)
                Slider(value: Binding(get: { Double(camera.focus) }, set: { camera.setFocus(Float($0)) }), in: 0...1)
                Text(String(format: "%.2f", camera.focus)).font(.caption.monospacedDigit()).frame(width: 48)
            }
            .disabled(!camera.capabilities.supportsManualFocus)
            .opacity(camera.capabilities.supportsManualFocus ? 1 : 0.35)

            Button { if camera.capabilities.supportsRAW { camera.rawEnabled.toggle() } } label: {
                Label(camera.rawEnabled ? "RAW enabled" : "RAW disabled", systemImage: camera.rawEnabled ? "checkmark.circle.fill" : "circle").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(camera.capabilities.supportsRAW ? 1 : 0.35)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var recipeSheet: some View {
        NavigationStack {
            List(CameraRecipe.builtIns) { recipe in
                Button {
                    camera.applyRecipe(recipe)
                    showRecipes = false
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(recipe.name).font(.headline)
                            Text("\(recipe.detailFrames) Detail frames\(recipe.rawEnabled ? " • RAW" : "")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if camera.activeRecipe.id == recipe.id { Image(systemName: "checkmark").foregroundStyle(.yellow) }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Camera Recipes")
        }
    }

    private var zoomPresets: [CGFloat] {
        camera.nativeZoomFactors
            .filter { $0 >= camera.minimumZoomFactor && $0 <= camera.maximumZoomFactor }
            .prefix(5)
            .map { $0 }
    }

    private func zoomLabel(_ factor: CGFloat) -> String {
        if abs(factor.rounded() - factor) < 0.01 {
            return "\(Int(factor))×"
        }
        return String(format: "%.1f×", factor)
    }

    private func shutter() {
        switch selectedMode {
        case .detail: camera.captureDetailBurst()
        case .photo, .pro: camera.capturePhoto()
        case .video: camera.toggleVideoRecording()
        case .spatial: break
        }
    }

    private var permissionView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill").font(.system(size: 42))
            Text("TideCam needs camera access").font(.title3.bold())
            Text("Allow camera access in Settings to start shooting.").foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}