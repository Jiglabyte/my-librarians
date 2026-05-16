import Foundation
import CoreGraphics

enum RecordingMode: Equatable, Hashable {
    case normal(fps: Int)
    case timeLapse(multiplier: Int)

    static let normalDefault: RecordingMode = .normal(fps: 30)
    static let timeLapseDefault: RecordingMode = .timeLapse(multiplier: 15)

    static let normalFPSOptions: [Int] = [25, 30, 60]
    static let timeLapseMultipliers: [Int] = [5, 10, 15, 30, 60]
    static let playbackFPS: Int32 = 30

    var captureFPS: Int {
        switch self {
        case .normal(let fps): return fps
        case .timeLapse(let mult): return max(1, Int(Self.playbackFPS) / mult)
        }
    }

    var label: String {
        switch self {
        case .normal(let fps): return "\(fps) fps"
        case .timeLapse(let mult): return "\(mult)× time-lapse"
        }
    }

    var isTimeLapse: Bool {
        if case .timeLapse = self { return true }
        return false
    }
}

enum CodecChoice: String, CaseIterable, Identifiable {
    case hevc
    case h264
    case proRes
    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .hevc:   return "HEVC  (H.265)"
        case .h264:   return "H.264"
        case .proRes: return "ProRes 422 HQ"
        }
    }

    var detail: String {
        switch self {
        case .hevc:   return "Recommended · small files, excellent quality · hardware-encoded on Apple Silicon"
        case .h264:   return "Maximum compatibility · plays on any device · slightly larger files than HEVC"
        case .proRes: return "True lossless · stores raw RGBA pixels, no colour conversion · large files (~500 MB/min at 1080p)"
        }
    }

    var displayName: String { shortName }
}

enum QualityPreset: String, CaseIterable, Identifiable {
    case low, medium, high, max
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        case .max:    return "Max"
        }
    }

    var settingsLabel: String {
        switch self {
        case .low:    return "Low  (~15 MB/min)"
        case .medium: return "Medium  (~60 MB/min)"
        case .high:   return "High  (~190 MB/min)"
        case .max:    return "Max  (QuickTime quality, variable size)"
        }
    }

    // nil = quality-based VBR, no bitrate cap (QuickTime mode)
    var qualityFactor: Float? {
        self == .max ? 1.0 : nil
    }

    func estimatedMBperMinute(forHeight height: Int) -> Int {
        guard qualityFactor == nil else { return 0 }
        return max(1, bitrate(for: height) / 1_000_000 * 60 / 8)
    }

    func bitrate(for height: Int) -> Int {
        let base: Int
        switch self {
        case .low:    base =  2_000_000
        case .medium: base =  8_000_000
        case .high:   base = 25_000_000
        case .max:    base =  0           // unused — qualityFactor drives encoding
        }
        let scale = max(1.0, Double(height) / 1080.0)
        return Int(Double(base) * scale)
    }
}

enum OutputResolution: String, CaseIterable, Identifiable {
    case native, fourK, twoK, fullHD, hd
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .native: return "Native"
        case .fourK: return "4K (2160p)"
        case .twoK: return "2K (1440p)"
        case .fullHD: return "1080p"
        case .hd: return "720p"
        }
    }

    var targetHeight: Int? {
        switch self {
        case .native: return nil
        case .fourK: return 2160
        case .twoK: return 1440
        case .fullHD: return 1080
        case .hd: return 720
        }
    }
}

enum WebcamCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum CaptureSource: Equatable, Hashable {
    case display(id: CGDirectDisplayID, name: String)
    case window(id: CGWindowID, title: String, app: String)
    case region(rect: CGRect, displayID: CGDirectDisplayID)

    var displayName: String {
        switch self {
        case .display(_, let name): return "Display: \(name)"
        case .window(_, let title, let app): return "\(app) — \(title)"
        case .region(let rect, _):
            return "Region \(Int(rect.width))×\(Int(rect.height))"
        }
    }
}
