import SwiftUI

struct CameraView: View {
    @StateObject private var camera = CameraManager()
    @State private var selectedMode = "PHOTO"

    private let modes = ["3D", "DETAIL", "PHOTO", "PRO", "VIDEO"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isAuthorized {
                CameraPreview(session: camera.session, onFocus: camera.focus)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.58), .clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                controls
            } else {
                permissionView
            }
        }
        .alert("TideCam", isPresented: Binding(
            get: { camera.errorMessage != nil },
            set: { if !$0 { camera.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { camera.errorMessage = nil }
        } message: {
            Text(camera.errorMessage ?? "Unknown camera error")
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: camera.cycleFlash) {
                    Image(systemName: camera.flashMode.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Spacer()

                Text("TIDECAM")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(2.2)

                Spacer()

                Button { } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 22) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 26) {
                        ForEach(modes, id: \.self) { mode in
                            Button {
                                selectedMode = mode
                            } label: {
                                Text(mode)
                                    .font(.system(size: 13, weight: selectedMode == mode ? .bold : .medium))
                                    .foregroundStyle(selectedMode == mode ? .yellow : .white.opacity(0.72))
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                }

                HStack {
                    Group {
                        if let image = camera.lastPhoto {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .frame(width: 54, height: 54)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                    Spacer()

                    Button(action: camera.capturePhoto) {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                            Circle()
                                .fill(.white)
                                .frame(width: camera.isCapturing ? 58 : 66, height: camera.isCapturing ? 58 : 66)
                        }
                    }
                    .disabled(selectedMode != "PHOTO" || camera.isCapturing)
                    .opacity(selectedMode == "PHOTO" ? 1 : 0.45)

                    Spacer()

                    Button(action: camera.switchCamera) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                            .font(.system(size: 23, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 18)
        }
    }

    private var permissionView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 42))
            Text("TideCam needs camera access")
                .font(.title3.bold())
            Text("Allow camera access in Settings to start shooting.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}
