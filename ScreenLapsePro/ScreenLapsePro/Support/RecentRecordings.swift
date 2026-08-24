// ScreenLapsePro
// Support/RecentRecordings.swift
// Persistent list of the most recently saved recordings

import Foundation
import AppKit

// MARK: - RecentRecording

struct RecentRecording: Identifiable, Codable, Hashable {
    let id: UUID
    let path: String
    let createdAt: Date
    let mode: String

    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { url.lastPathComponent }
    var fileExists: Bool { FileManager.default.fileExists(atPath: path) }
}

// MARK: - RecentRecordingsStore

/// Persists the last few recordings in UserDefaults so the popover can list
/// them across launches.
@MainActor
final class RecentRecordingsStore: ObservableObject {

    // MARK: Public

    static let shared = RecentRecordingsStore()

    /// The most recent recording is first.
    @Published private(set) var items: [RecentRecording] = []

    // MARK: Private

    private let key = "recentRecordings"
    private let maxCount = 8

    private init() {
        load()
    }

    // MARK: API

    func add(url: URL, mode: String) {
        let entry = RecentRecording(id: UUID(), path: url.path, createdAt: Date(), mode: mode)
        items.insert(entry, at: 0)
        if items.count > maxCount {
            items.removeLast(items.count - maxCount)
        }
        save()
    }

    func remove(_ entry: RecentRecording) {
        items.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func revealInFinder(_ entry: RecentRecording) {
        NSWorkspace.shared.selectFile(
            entry.path,
            inFileViewerRootedAtPath: entry.url.deletingLastPathComponent().path
        )
    }

    func open(_ entry: RecentRecording) {
        NSWorkspace.shared.open(entry.url)
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        items = (try? JSONDecoder().decode([RecentRecording].self, from: data)) ?? []
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
