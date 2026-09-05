import Foundation

struct CameraRecipe: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var iso: Float?
    var focus: Float?
    var rawEnabled: Bool
    var detailFrames: Int

    init(id: UUID = UUID(), name: String, iso: Float? = nil, focus: Float? = nil, rawEnabled: Bool = false, detailFrames: Int = 8) {
        self.id = id
        self.name = name
        self.iso = iso
        self.focus = focus
        self.rawEnabled = rawEnabled
        self.detailFrames = detailFrames
    }

    static let builtIns: [CameraRecipe] = [
        .init(name: "Everyday", rawEnabled: false, detailFrames: 8),
        .init(name: "Maximum Detail", rawEnabled: false, detailFrames: 16),
        .init(name: "Tripod Detail", iso: 50, rawEnabled: false, detailFrames: 24),
        .init(name: "RAW Base", rawEnabled: true, detailFrames: 8)
    ]
}
