import PhotosUI
import SwiftUI

struct TideCamLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = TideCamLibraryStore.shared
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selectedItem: TideCamLibraryItem?
    @State private var showImportAllConfirmation = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 46))
                            .foregroundStyle(.secondary)
                        Text("Your TideCam Library")
                            .font(.title3.bold())
                        Text("Photos you take in TideCam and photos you import from Apple Photos will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(store.items) { item in
                                Button {
                                    selectedItem = item
                                } label: {
                                    TideCamLibraryThumbnail(item: item)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    ShareLink(item: item.url) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive) {
                                        store.delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .background(Color.black)
                }
            }
            .navigationTitle("TideCam Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Camera") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 50,
                        matching: .images
                    ) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(store.isImporting)

                    Button("Import All") {
                        showImportAllConfirmation = true
                    }
                    .disabled(store.isImporting)
                }
            }
            .overlay {
                if store.isImporting {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        ProgressView(store.importProgressText ?? "Importing…")
                            .padding(18)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .onAppear { store.refresh() }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await store.importFromPhotos(newItems)
                    pickerItems = []
                }
            }
            .confirmationDialog(
                "Import your entire Photos library?",
                isPresented: $showImportAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Import All Photos") {
                    Task { await store.importAllPhotos() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("TideCam will copy every photo it can access into its own library. This can use a lot of storage for large photo libraries.")
            }
            .fullScreenCover(item: $selectedItem) { item in
                TideCamPhotoViewer(item: item)
            }
            .alert("TideCam Photos", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "Unknown library error")
            }
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

private struct TideCamPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let item: TideCamLibraryItem

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
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
                } else if let image = UIImage(contentsOfFile: item.url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Photo unavailable", systemImage: "photo")
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: item.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}