// ScreenLapsePro
// Support/Prefs.swift
// UserDefaults keys and preference accessors

import Foundation
import SwiftUI

// MARK: - Key Constants

enum PrefsKey {
    static let recordingMode        = "recordingMode"
    static let timeLapseMultiplier  = "timeLapseMultiplier"
    static let frameRate            = "frameRate"
    static let outputFolder         = "outputFolder"
    static let showCursor           = "showCursor"
    static let useHEVC              = "useHEVC"
}

// MARK: - Default Values

private enum PrefsDefault {
    static let recordingMode        = "normal"
    static let timeLapseMultiplier  = 15
    static let frameRate            = 30
    static let outputFolder: String = {
        let movies = FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        return movies.appendingPathComponent("ScreenLapsePro").path
    }()
    static let showCursor           = true
    static let useHEVC              = true
}

// MARK: - Prefs

/// Centralised access to UserDefaults preferences.
/// Mirrors the shape of @AppStorage but works outside SwiftUI.
final class Prefs {

    // Singleton only used from non-SwiftUI code; SwiftUI views use @AppStorage directly.
    static let shared = Prefs()
    private init() { registerDefaults() }

    private func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefsKey.recordingMode:       PrefsDefault.recordingMode,
            PrefsKey.timeLapseMultiplier: PrefsDefault.timeLapseMultiplier,
            PrefsKey.frameRate:           PrefsDefault.frameRate,
            PrefsKey.outputFolder:        PrefsDefault.outputFolder,
            PrefsKey.showCursor:          PrefsDefault.showCursor,
            PrefsKey.useHEVC:             PrefsDefault.useHEVC,
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

    static var outputFolder: String {
        get { UserDefaults.standard.string(forKey: PrefsKey.outputFolder) ?? PrefsDefault.outputFolder }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.outputFolder) }
    }

    static var showCursor: Bool {
        get { UserDefaults.standard.bool(forKey: PrefsKey.showCursor) }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.showCursor) }
    }

    static var useHEVC: Bool {
        get { UserDefaults.standard.bool(forKey: PrefsKey.useHEVC) }
        set { UserDefaults.standard.set(newValue, forKey: PrefsKey.useHEVC) }
    }

    // MARK: Output URL helper

    /// Generates a timestamped output URL inside the chosen output folder.
    static func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename  = "ScreenLapsePro_\(timestamp).mp4"
        let folder    = URL(fileURLWithPath: outputFolder)
        return folder.appendingPathComponent(filename)
    }

    /// Creates the output folder if it does not already exist.
    static func ensureOutputFolderExists() throws {
        let url = URL(fileURLWithPath: outputFolder)
        try FileManager.default.createDirectory(at: url,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }
}
