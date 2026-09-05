import Foundation

enum CameraMode: String, CaseIterable, Identifiable {
    case spatial = "3D"
    case detail = "DETAIL"
    case photo = "PHOTO"
    case pro = "PRO"
    case video = "VIDEO"

    var id: String { rawValue }

    var isImplemented: Bool {
        switch self {
        case .photo, .detail, .pro, .video: return true
        case .spatial: return false
        }
    }
}

struct CameraCapabilities: Equatable {
    var supportsRAW = false
    var supportsManualFocus = false
    var supportsCustomExposure = false
    var supportsTorch = false
    var supportsDepth = false
    var supportsVideo = false
    var minimumISO: Float = 0
    var maximumISO: Float = 0
}
