import Foundation

struct RecentRecording: Identifiable, Codable, Equatable {
    var id: UUID
    var url: URL
    var modeLabel: String
    var capturedAt: Date
    var realDuration: TimeInterval
    var outputDuration: TimeInterval
    var fileSize: Int64
}

final class RecentRecordings {
    static let shared = RecentRecordings()

    private let key = "ScreenLapse.recentRecordings"
    private let maxItems = 25

    private(set) var items: [RecentRecording]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RecentRecording].self, from: data) {
            self.items = decoded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        } else {
            self.items = []
        }
    }

    func add(_ recording: RecentRecording) {
        items.insert(recording, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func reload() {
        items = items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
