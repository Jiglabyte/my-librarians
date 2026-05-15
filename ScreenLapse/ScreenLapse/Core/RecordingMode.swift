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
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .hevc: return "HEVC (H.265) — recommended"
        case .h264: return "H.264 — maximum compatibility"
        }
    }
}

enum QualityPreset: String, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    func bitrate(for height: Int) -> Int {
        // Wide spread so there's a clearly visible difference between presets.
        // Low looks noticeably softer on fine text/detail; High is near-lossless.
        let base: Int
        switch self {
        case .low:    base =  2_000_000   //  2 Mbps — visible compression on detail
        case .medium: base =  8_000_000   //  8 Mbps — good balance, default
        case .high:   base = 25_000_000   // 25 Mbps — near-lossless for screen content
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
