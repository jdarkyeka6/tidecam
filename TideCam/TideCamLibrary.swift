import Foundation
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

enum TideLibrarySource: String, CaseIterable, Identifiable {
    case all
    case tideCam
    case applePhotos
    case googleDrive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .tideCam: return "TideCam"
        case .applePhotos: return "Photos"
        case .googleDrive: return "Drive"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .tideCam: return "camera.fill"
        case .applePhotos: return "apple.logo"
        case .googleDrive: return "externaldrive.fill"
        }
    }
}

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

struct TidePhotoAsset: Identifiable, Hashable {
    let id: String
    let createdAt: Date
    let mediaType: PHAssetMediaType
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval

    var isVideo: Bool { mediaType == .video }
}

enum TideLibraryEntry: Identifiable, Hashable {
    case tideCam(TideCamLibraryItem)
    case applePhotos(TidePhotoAsset)

    var id: String {
        switch self {
        case .tideCam(let item): return "tidecam:\(item.id)"
        case .applePhotos(let asset): return "photos:\(asset.id)"
        }
    }

    var createdAt: Date {
        switch self {
        case .tideCam(let item): return item.createdAt
        case .applePhotos(let asset): return asset.createdAt
        }
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
    @Published private(set) var photoAssets: [TidePhotoAsset] = []
    @Published private(set) var allEntries: [TideLibraryEntry] = []
    @Published private(set) var photoAuthorizationStatus: PHAuthorizationStatus
    @Published var errorMessage: String?

    private init() {
        photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        refresh()
        if canReadApplePhotos {
            refreshApplePhotos()
        }
    }

    var canReadApplePhotos: Bool {
        photoAuthorizationStatus == .authorized || photoAuthorizationStatus == .limited
    }

    var photoAccessDenied: Bool {
        photoAuthorizationStatus == .denied || photoAuthorizationStatus == .restricted
    }

    func entries(for source: TideLibrarySource) -> [TideLibraryEntry] {
        switch source {
        case .all:
            return allEntries
        case .tideCam:
            return items.map(TideLibraryEntry.tideCam)
        case .applePhotos:
            return photoAssets.map(TideLibraryEntry.applePhotos)
        case .googleDrive:
            return []
        }
    }

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
            rebuildCombinedEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func ensurePhotoLibraryAccess() async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let resolved: PHAuthorizationStatus

        if current == .notDetermined {
            resolved = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    continuation.resume(returning: status)
                }
            }
        } else {
            resolved = current
        }

        photoAuthorizationStatus = resolved

        if canReadApplePhotos {
            refreshApplePhotos()
        } else {
            photoAssets = []
            rebuildCombinedEntries()
        }
    }

    func refreshApplePhotos() {
        guard canReadApplePhotos else {
            photoAssets = []
            rebuildCombinedEntries()
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let result = PHAsset.fetchAssets(with: options)
        var fetched: [TidePhotoAsset] = []
        fetched.reserveCapacity(result.count)

        result.enumerateObjects { asset, _, _ in
            guard asset.mediaType == .image || asset.mediaType == .video else { return }
            fetched.append(
                TidePhotoAsset(
                    id: asset.localIdentifier,
                    createdAt: asset.creationDate ?? .distantPast,
                    mediaType: asset.mediaType,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    duration: asset.duration
                )
            )
        }

        photoAssets = fetched
        rebuildCombinedEntries()
    }

    func delete(_ item: TideCamLibraryItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            refresh()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func rebuildCombinedEntries() {
        let local = items.map(TideLibraryEntry.tideCam)
        let photos = photoAssets.map(TideLibraryEntry.applePhotos)
        allEntries = (local + photos).sorted { $0.createdAt > $1.createdAt }
    }
}
