import Foundation
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct TideCamLibraryItem: Identifiable, Hashable {
    let url: URL

    var id: String { url.path }
    var isRAW: Bool { url.pathExtension.lowercased() == "dng" }
    var isVideo: Bool {
        ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
    }
    var createdAt: Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}

enum TideCamLibraryStorage {
    private static let folderName = "TideCam Library"

    static func directoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func save(_ data: Data, preferredExtension: String? = nil) throws -> URL {
        let ext = preferredExtension ?? detectedExtension(for: data)
        let filename = "TideCam-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6)).\(ext)"
        let url = try directoryURL().appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func saveFile(from sourceURL: URL, preferredExtension: String? = nil) throws -> URL {
        let ext = preferredExtension ?? sourceURL.pathExtension.lowercased()
        let finalExtension = ext.isEmpty ? "dat" : ext
        let filename = "TideCam-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6)).\(finalExtension)"
        let destination = try directoryURL().appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    static func detectedExtension(for data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return "jpg" }
        return UTType(type as String)?.preferredFilenameExtension ?? "jpg"
    }
}

@MainActor
final class TideCamLibraryStore: ObservableObject {
    static let shared = TideCamLibraryStore()

    @Published private(set) var items: [TideCamLibraryItem] = []
    @Published var isImporting = false
    @Published var importProgressText: String?
    @Published var errorMessage: String?

    private let importedAssetIDsKey = "TideCamImportedPhotoAssetIDs"

    private init() { refresh() }

    func refresh() {
        do {
            let directory = try TideCamLibraryStorage.directoryURL()
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            items = urls
                .map(TideCamLibraryItem.init(url:))
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFromPhotos(_ selections: [PhotosPickerItem]) async {
        guard !selections.isEmpty else { return }
        isImporting = true
        importProgressText = "Importing selected photos…"
        defer {
            isImporting = false
            importProgressText = nil
        }

        for selection in selections {
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else { continue }
                let ext = selection.supportedContentTypes.first?.preferredFilenameExtension
                _ = try TideCamLibraryStorage.save(data, preferredExtension: ext)
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }
        }
        refresh()
    }

    func importAllPhotos() async {
        guard !isImporting else { return }
        isImporting = true
        importProgressText = "Requesting Photos access…"
        defer {
            isImporting = false
            importProgressText = nil
        }

        let status = await requestPhotoLibraryAccess()
        guard status == .authorized || status == .limited else {
            errorMessage = "TideCam needs Photos access to import your library."
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        guard assets.count > 0 else {
            importProgressText = "No photos found"
            return
        }

        var importedIDs = Set(UserDefaults.standard.stringArray(forKey: importedAssetIDsKey) ?? [])
        var importedCount = 0
        var skippedCount = 0

        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            if importedIDs.contains(asset.localIdentifier) {
                skippedCount += 1
                continue
            }

            importProgressText = "Importing \(index + 1) of \(assets.count)"

            do {
                guard let payload = await originalImageData(for: asset) else {
                    skippedCount += 1
                    continue
                }
                _ = try TideCamLibraryStorage.save(payload.data, preferredExtension: payload.fileExtension)
                importedIDs.insert(asset.localIdentifier)
                importedCount += 1
            } catch {
                skippedCount += 1
            }
        }

        UserDefaults.standard.set(Array(importedIDs), forKey: importedAssetIDsKey)
        refresh()

        if importedCount == 0 && skippedCount > 0 {
            errorMessage = "Nothing new to import. Your accessible Photos library is already in TideCam."
        }
    }

    private func requestPhotoLibraryAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func originalImageData(for asset: PHAsset) async -> (data: Data, fileExtension: String?)? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .original
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                let ext = uti.flatMap { UTType($0)?.preferredFilenameExtension }
                continuation.resume(returning: (data, ext))
            }
        }
    }

    func delete(_ item: TideCamLibraryItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            refresh()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}