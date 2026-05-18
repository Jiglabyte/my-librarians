// ScreenLapsePro
// Support/Prefs.swift
// UserDefaults keys and preference accessors

import Foundation
import SwiftUI

// MARK: - Key Constants

enum PrefsKey {
    // Video
    static let recordingMode        = "recordingMode"
    static let timeLapseMultiplier  = "timeLapseMultiplier"
    static let frameRate            = "frameRate"
    static let useHEVC              = "useHEVC"
    static let videoBitratePreset   = "videoBitratePreset"

    // Audio
    static let recordSystemAudio    = "recordSystemAudio"
    static let recordMicrophone     = "recordMicrophone"

    // Capture
    static let showCursor           = "showCursor"
    static let outputFolder         = "outputFolder"

    // Recording behavior
    static let countdownSeconds     = "countdownSeconds"
    static let autoStopMinutes      = "autoStopMinutes"
    static let preventSleep         = "preventSleep"

    // Display
    static let showFloatingPill     = "showFloatingPill"
    static let showStatusBarTimer   = "showStatusBarTimer"
}

// MARK: - Bitrate Preset

enum BitratePreset: String, CaseIterable {
    case low    = "low"
    case medium = "medium"
    case high   = "high"
    case ultra  = "ultra"

    var label: String {
        switch self {
        case .low:    return "Low (1 Mbps)"
        case .medium: return "Medium (4 Mbps)"
        case .high:   return "High (10 Mbps)"
        case .ultra:  return "Ultra (20 Mbps)"
        }
    }

    func bitrate(forPixelCount pixels: Int) -> Int {
        let base: Int
        switch self {
        case .low:    base = 1_000_000
        case .medium: base = 4_000_000
        case .high:   base = 10_000_000
        case .ultra:  base = 20_000_000
        }
        return Swift.max(500_000, Int(Double(base) * Double(pixels) / Double(1920 * 1080)))
    }
}

// MARK: - Default Values

private enum PrefsDefault {
    static let recordingMode        = "normal"
    static let timeLapseMultiplier  = 15
    static let frameRate            = 30
    static let useHEVC              = true
    static let videoBitratePreset   = BitratePreset.medium.rawValue
    static let recordSystemAudio    = false
    static let recordMicrophone     = false
    static let showCursor           = true
    static let outputFolder: String = {
        let movies = FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        return movies.appendingPathComponent("ScreenLapsePro").path
    }()
    static let countdownSeconds     = 3
    static let autoStopMinutes      = 0
    static let preventSleep         = true
    static let showFloatingPill     = true
    static let showStatusBarTimer   = true
}

// MARK: - Prefs

/// Centralised access to UserDefaults preferences.
final class Prefs {

    static let shared = Prefs()
    private init() { registerDefaults() }

    private func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefsKey.recordingMode:       PrefsDefault.recordingMode,
            PrefsKey.timeLapseMultiplier: PrefsDefault.timeLapseMultiplier,
            PrefsKey.frameRate:           PrefsDefault.frameRate,
            PrefsKey.useHEVC:             PrefsDefault.useHEVC,
            PrefsKey.videoBitratePreset:  PrefsDefault.videoBitratePreset,
            PrefsKey.recordSystemAudio:   PrefsDefault.recordSystemAudio,
            PrefsKey.recordMicrophone:    PrefsDefault.recordMicrophone,
            PrefsKey.showCursor:          PrefsDefault.showCursor,
            PrefsKey.outputFolder:        PrefsDefault.outputFolder,
            PrefsKey.countdownSeconds:    PrefsDefault.countdownSeconds,
            PrefsKey.autoStopMinutes:     PrefsDefault.autoStopMinutes,
            PrefsKey.preventSleep:        PrefsDefault.preventSleep,
            PrefsKey.showFloatingPill:    PrefsDefault.showFloatingPill,
            PrefsKey.showStatusBarTimer:  PrefsDefault.showStatusBarTimer,
        ])
    }

    // MARK: Computed accessors

    static var recordingMode: String {
        get { UserDefaults.standard.string(forKey: PrefsKey.recordingMode) ?? PrefsDefault.recordingMode }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.recordingMode) }
    }

    static var timeLapseMultiplier: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: PrefsKey.timeLapseMultiplier)
            return v == 0 ? PrefsDefault.timeLapseMultiplier : v
        }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.timeLapseMultiplier) }
    }

    static var frameRate: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: PrefsKey.frameRate)
            return v == 0 ? PrefsDefault.frameRate : v
        }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.frameRate) }
    }

    static var useHEVC: Bool {
        get { UserDefaults.standard.bool(forKey: PrefsKey.useHEVC) }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.useHEVC) }
    }

    static var videoBitratePreset: BitratePreset {
        get {
            let raw = UserDefaults.standard.string(forKey: PrefsKey.videoBitratePreset) ?? PrefsDefault.videoBitratePreset
            return BitratePreset(rawValue: raw) ?? .medium
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: PrefsKey.videoBitratePreset) }
    }

    static var recordSystemAudio: Bool {
        get { UserDefaults.standard.bool(forKey: PrefsKey.recordSystemAudio) }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.recordSystemAudio) }
    }

    static var recordMicrophone: Bool {
        get { UserDefaults.standard.bool(forKey: PrefsKey.recordMicrophone) }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.recordMicrophone) }
    }

    static var showCursor: Bool {
        get { UserDefaults.standard.bool(forKey: PrefsKey.showCursor) }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.showCursor) }
    }

    static var outputFolder: String {
        get { UserDefaults.standard.string(forKey: PrefsKey.outputFolder) ?? PrefsDefault.outputFolder }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.outputFolder) }
    }

    static var countdownSeconds: Int {
        get { UserDefaults.standard.integer(forKey: PrefsKey.countdownSeconds) }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.countdownSeconds) }
    }

    static var autoStopMinutes: Int {
        get { UserDefaults.standard.integer(forKey: PrefsKey.autoStopMinutes) }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.autoStopMinutes) }
    }

    static var preventSleep: Bool {
        get { UserDefaults.standard.bool(forKey: PrefsKey.preventSleep) }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.preventSleep) }
    }

    static var showFloatingPill: Bool {
        get { UserDefaults.standard.bool(forKey: PrefsKey.showFloatingPill) }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.showFloatingPill) }
    }

    static var showStatusBarTimer: Bool {
        get { UserDefaults.standard.bool(forKey: PrefsKey.showStatusBarTimer) }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.showStatusBarTimer) }
    }

    // MARK: Output URL helper

    static func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename  = "ScreenLapsePro_\(timestamp).mp4"
        let folder    = URL(fileURLWithPath: outputFolder)
        return folder.appendingPathComponent(filename)
    }

    static func ensureOutputFolderExists() throws {
        let url = URL(fileURLWithPath: outputFolder)
        try FileManager.default.createDirectory(at: url,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }
}
