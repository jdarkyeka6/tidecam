import AVKit
import Photos
import SwiftUI

struct TideCamLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = TideCamLibraryStore.shared
    @State private var selectedSource: TideLibrarySource = .all
    @State private var selectedEntry: TideLibraryEntry?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var visibleEntries: [TideLibraryEntry] {
        store.entries(for: selectedSource)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sourcePicker
                content
            }
            .background(Color.black)
            .navigationTitle("TideLibrary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Camera") { dismiss() }
                }
            }
            .task {
                await store.ensurePhotoLibraryAccess()
            }
            .onAppear {
                store.refresh()
                if store.canReadApplePhotos {
                    store.refreshApplePhotos()
                }
            }
            .fullScreenCover(item: $selectedEntry) { entry in
                TideLibraryViewer(entry: entry)
            }
            .alert("TideLibrary", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "Unknown library error")
            }
        }
    }

    private var sourcePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TideLibrarySource.allCases) { source in
                    Button {
                        withAnimation(.snappy) {
                            selectedSource = source
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: source.symbol)
                            Text(source.title)
                            if source != .googleDrive {
                                Text("\(count(for: source))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(selectedSource == source ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedSource == source ? Color.white : Color.white.opacity(0.1),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.black)
    }

    @ViewBuilder
    private var content: some View {
        if selectedSource == .googleDrive {
            drivePlaceholder
        } else if selectedSource == .applePhotos && store.photoAccessDenied {
            photosPermissionView
        } else if visibleEntries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(visibleEntries) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            TideLibraryThumbnail(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            switch entry {
                            case .tideCam(let item):
                                ShareLink(item: item.url) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                Button(role: .destructive) {
                                    store.delete(item)
                                } label: {
                                    Label("Delete from TideCam", systemImage: "trash")
                                }
                            case .applePhotos:
                                Label("Stored in Apple Photos", systemImage: "icloud")
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: selectedSource == .applePhotos ? "photo.stack" : "camera")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.title3.bold())
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var photosPermissionView: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Apple Photos access is off")
                .font(.title3.bold())
            Text("TideLibrary can show your Apple Photos without copying the full library into TideCam.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var drivePlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Google Drive")
                .font(.title3.bold())
            Text("The source is wired into TideLibrary's layout, but account connection is not enabled in this build yet. Nothing is downloaded or duplicated.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            Label("Next: connect a Drive folder", systemImage: "link")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func count(for source: TideLibrarySource) -> Int {
        switch source {
        case .all: return store.allEntries.count
        case .tideCam: return store.items.count
        case .applePhotos: return store.photoAssets.count
        case .googleDrive: return 0
        }
    }

    private var emptyTitle: String {
        switch selectedSource {
        case .all: return "Nothing here yet"
        case .tideCam: return "No TideCam captures yet"
        case .applePhotos: return "No accessible Apple Photos"
        case .googleDrive: return "Google Drive"
        }
    }

    private var emptyMessage: String {
        switch selectedSource {
        case .all:
            return "Shoot something in TideCam or allow Apple Photos access."
        case .tideCam:
            return "Photos and videos captured by TideCam appear here."
        case .applePhotos:
            return store.canReadApplePhotos
                ? "TideLibrary is connected, but no accessible photos or videos were found."
                : "Allow Photos access to browse your library without duplicating it."
        case .googleDrive:
            return ""
        }
    }
}

private struct TideLibraryThumbnail: View {
    let entry: TideLibraryEntry

    var body: some View {
        switch entry {
        case .tideCam(let item):
            TideCamLibraryThumbnail(item: item)
        case .applePhotos(let asset):
            TidePhotoThumbnail(asset: asset)
        }
    }
}

private struct TideCamLibraryThumbnail: View {
    let item: TideCamLibraryItem

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.08))
            if item.isRAW {
                VStack(spacing: 5) {
                    Image(systemName: "camera.aperture")
                        .font(.title2)
                    Text("RAW")
                        .font(.caption2.bold())
                }
                .foregroundStyle(.white)
            } else if item.isVideo {
                VStack(spacing: 5) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2)
                    Text("VIDEO")
                        .font(.caption2.bold())
                }
                .foregroundStyle(.white)
            } else if let image = UIImage(contentsOfFile: item.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

private struct TidePhotoThumbnail: View {
    let asset: TidePhotoAsset
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle().fill(Color.white.opacity(0.08))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "icloud")
                        .font(.title3)
                    Text("CLOUD")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.secondary)
            }

            if asset.isVideo {
                Image(systemName: "play.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .onAppear(perform: load)
        .onDisappear(perform: cancel)
    }

    private func load() {
        guard image == nil else { return }
        guard let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil).firstObject else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let scale = UIScreen.main.scale
        let target = CGSize(width: 220 * scale, height: 220 * scale)

        requestID = PHCachingImageManager.default().requestImage(
            for: phAsset,
            targetSize: target,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            guard let result else { return }
            DispatchQueue.main.async {
                self.image = result
            }
        }
    }

    private func cancel() {
        guard requestID != PHInvalidImageRequestID else { return }
        PHCachingImageManager.default().cancelImageRequest(requestID)
        requestID = PHInvalidImageRequestID
    }
}

private struct TideLibraryViewer: View {
    @Environment(\.dismiss) private var dismiss
    let entry: TideLibraryEntry

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch entry {
                case .tideCam(let item):
                    TideCamLocalViewer(item: item)
                case .applePhotos(let asset):
                    TidePhotoAssetViewer(asset: asset)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }

                if case .tideCam(let item) = entry {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: item.url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
}

private struct TideCamLocalViewer: View {
    let item: TideCamLibraryItem

    var body: some View {
        if item.isRAW {
            VStack(spacing: 12) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 56))
                Text("RAW / DNG")
                    .font(.headline)
                Text("TideCam keeps the original RAW file for editing or sharing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .foregroundStyle(.white)
        } else if item.isVideo {
            VideoPlayer(player: AVPlayer(url: item.url))
                .ignoresSafeArea(edges: .bottom)
        } else if let image = UIImage(contentsOfFile: item.url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea(edges: .bottom)
        } else {
            ContentUnavailableView("Photo unavailable", systemImage: "photo")
        }
    }
}

private struct TidePhotoAssetViewer: View {
    let asset: TidePhotoAsset

    @State private var image: UIImage?
    @State private var playerItem: AVPlayerItem?
    @State private var isLoading = true
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        Group {
            if asset.isVideo {
                if let playerItem {
                    VideoPlayer(player: AVPlayer(playerItem: playerItem))
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    loadingView
                }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea(edges: .bottom)
            } else {
                loadingView
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: cancel)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text(isLoading ? "Loading preview from Apple Photos…" : "Preview unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("TideLibrary does not create a second full-resolution copy.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func load() {
        guard let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil).firstObject else {
            isLoading = false
            return
        }

        if asset.isVideo {
            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestPlayerItem(forVideo: phAsset, options: options) { item, _ in
                DispatchQueue.main.async {
                    self.playerItem = item
                    self.isLoading = false
                }
            }
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let scale = UIScreen.main.scale
        let bounds = UIScreen.main.bounds
        let target = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        requestID = PHImageManager.default().requestImage(
            for: phAsset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            DispatchQueue.main.async {
                if let result {
                    self.image = result
                }
                if !degraded {
                    self.isLoading = false
                }
            }
        }
    }

    private func cancel() {
        guard requestID != PHInvalidImageRequestID else { return }
        PHImageManager.default().cancelImageRequest(requestID)
        requestID = PHInvalidImageRequestID
    }
}
