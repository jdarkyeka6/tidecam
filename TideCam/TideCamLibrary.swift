import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct TideCamLibraryItem: Identifiable, Hashable {
    let url: URL

    var id: String { url.path }
    var isRAW: Bool { url.pathExtension.lowercased() == "dng" }
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
    @Published var errorMessage: String?

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
        defer { isImporting = false }

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

    func delete(_ item: TideCamLibraryItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            refresh()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}