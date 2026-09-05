import SwiftUI

struct CameraView: View {
    @StateObject private var camera = CameraManager()
    @State private var selectedMode: CameraMode = .photo
    @State private var showRecipes = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.isAuthorized {
                CameraPreview(session: camera.session, onFocus: camera.focus).ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.58), .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
                controls
            } else { permissionView }
        }
        .sheet(isPresented: $showRecipes) { recipeSheet.presentationDetents([.medium]) }
        .alert("TideCam", isPresented: Binding(get: { camera.errorMessage != nil }, set: { if !$0 { camera.errorMessage = nil } })) {
            Button("OK", role: .cancel) { camera.errorMessage = nil }
        } message: {
            Text(camera.errorMessage ?? "Unknown camera error")
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: camera.cycleFlash) {
                    Image(systemName: camera.flashMode.symbol).font(.system(size: 19, weight: .semibold)).frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                }
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
            if selectedMode == .pro { proPanel.transition(.move(edge: .bottom).combined(with: .opacity)) }
            if selectedMode == .detail { detailPanel.transition(.move(edge: .bottom).combined(with: .opacity)) }
            if selectedMode == .video { videoPanel.transition(.move(edge: .bottom).combined(with: .opacity)) }

            VStack(spacing: 22) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 26) {
                        ForEach(CameraMode.allCases) { mode in
                            Button {
                                withAnimation(.snappy) { selectedMode = mode }
                            } label: {
                                VStack(spacing: 3) {
                                    Text(mode.rawValue).font(.system(size: 13, weight: selectedMode == mode ? .bold : .medium))
                                    if !mode.isImplemented { Text("SOON").font(.system(size: 7, weight: .bold)) }
                                }
                                .foregroundStyle(selectedMode == mode ? .yellow : .white.opacity(mode.isImplemented ? 0.72 : 0.38))
                            }
                            .disabled(camera.isRecording || camera.isPreparingVideo)
                        }
                    }
                    .padding(.horizontal, 30)
                }

                HStack {
                    Group {
                        if let image = camera.lastPhoto {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo").font(.title3).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .frame(width: 54, height: 54)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                    Spacer()

                    Button(action: shutter) {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                            shutterFill
                        }
                    }
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
        } else {
            Circle().fill(selectedMode == .detail ? .yellow : .white).frame(width: camera.isCapturing ? 58 : 66, height: camera.isCapturing ? 58 : 66)
        }
    }

    private var shutterDisabled: Bool {
        if selectedMode == .video {
            return !camera.capabilities.supportsVideo || camera.isPreparingVideo || camera.isCapturing
        }
        return !selectedMode.isImplemented || camera.isCapturing || camera.isRecording || camera.isPreparingVideo
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
            Text(camera.isCapturing ? "Hold still while TideCam collects the cleanest information from the scene." : "More frames can improve the source data but take longer to capture.").font(.caption2).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var videoPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: camera.isRecording ? "record.circle.fill" : "video.fill").foregroundStyle(camera.isRecording ? .red : .white)
            VStack(alignment: .leading, spacing: 2) {
                Text(camera.isRecording ? "RECORDING" : camera.isPreparingVideo ? "PREPARING VIDEO" : "VIDEO").font(.caption.bold()).tracking(1)
                Text(camera.capabilities.supportsVideo ? "Tap the red button to \(camera.isRecording ? "stop and save" : "start recording")." : "Video is unavailable on this camera.").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
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
