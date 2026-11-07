//
//  ExportCodec.swift
//  Movie Editor
//

import Foundation

enum ExportCodec: String, CaseIterable, Identifiable {
    case h264 = "H264"
    case h265 = "H265"
    case proRes = "ProRes"

    static let storageKey = "exportCodec"

    var id: String { rawValue }

    var preset: String {
        switch self {
        case .h264:   return "AVAssetExportPresetHighestQuality"
        case .h265:   return "AVAssetExportPresetHEVCHighestQuality"
        case .proRes: return "AVAssetExportPresetAppleProRes422LPCM"
        }
    }

    /// The codec chosen in Settings.
    static var current: ExportCodec {
        ExportCodec(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .h264
    }
}
