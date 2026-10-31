import SwiftUI

@main
struct TideCamWatchApp: App {
    @StateObject private var remote = RemoteModel()

    var body: some Scene {
        WindowGroup {
            RemoteView(remote: remote)
                .onAppear { remote.start() }
        }
    }
}

struct RemoteView: View {
    @ObservedObject var remote: RemoteModel

    private var canShoot: Bool {
        remote.connected && remote.phoneReady && !remote.busy
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 11) {
                HStack(spacing: 6) {
                    Image(systemName: remote.connected ? "iphone.gen3.radiowaves.left.and.right" : "iphone.slash")
                        .foregroundStyle(remote.connected ? .green : .orange)
                    Text(remote.connected ? "CONNECTED" : "DISCONNECTED")
                        .font(.system(size: 10, weight: .heavy))
                    Spacer()
                    Text(remote.mode)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.yellow)
                }

                Button {
                    remote.command("photo")
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                        Text("TAKE PHOTO")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .disabled(!canShoot || remote.recording || remote.bursting)

                HStack(spacing: 8) {
                    Button {
                        remote.command("video")
                    } label: {
                        Label(remote.recording ? "STOP" : "REC",
                              systemImage: remote.recording ? "stop.fill" : "record.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(remote.recording ? .red : .gray)
                    .disabled(!canShoot || remote.bursting)

                    Button {
                        remote.command("burst")
                    } label: {
                        Label(remote.bursting ? "END" : "BURST",
                              systemImage: "circle.grid.3x3.fill")
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(remote.bursting ? .orange : .gray)
                    .disabled(!canShoot || remote.recording)
                }
                .buttonStyle(.bordered)

                if remote.bursting {
                    Text("\(remote.burstCount) shots")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(.yellow)
                }

                HStack(spacing: 8) {
                    Button {
                        remote.command("zoom", value: max(remote.minZoom, remote.zoom - 0.5))
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(!canShoot || remote.zoom <= remote.minZoom)

                    Text(String(format: "%.1f×", remote.zoom))
                        .font(.caption.monospacedDigit().bold())
                        .frame(maxWidth: .infinity)

                    Button {
                        remote.command("zoom", value: min(remote.maxZoom, remote.zoom + 0.5))
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .disabled(!canShoot || remote.zoom >= remote.maxZoom)
                }
                .buttonStyle(.bordered)

                Button {
                    remote.command("flip")
                } label: {
                    Label("SWITCH CAMERA", systemImage: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 11, weight: .bold))
                }
                .disabled(!canShoot || remote.recording || remote.bursting)

                Text(remote.feedback)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
        }
        .navigationTitle("TideCam")
    }
}
