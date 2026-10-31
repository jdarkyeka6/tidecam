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

enum VideoQuality: String, CaseIterable, Identifiable {
    case uhd60 = "4K 60"
    case uhd30 = "4K 30"
    case fhd60 = "1080p 60"
    case fhd30 = "1080p 30"

    var id: String { rawValue }
    var width: Int32 { self == .uhd60 || self == .uhd30 ? 3840 : 1920 }
    var height: Int32 { self == .uhd60 || self == .uhd30 ? 2160 : 1080 }
    var fps: Int32 { self == .uhd60 || self == .fhd60 ? 60 : 30 }
}
