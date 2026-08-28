import Foundation

/// Small amounts of persistent state: where you stopped watching, and what
/// you searched for. Both are tiny and disposable, so UserDefaults is the
/// right tool; nothing here justifies a database.
enum PlaybackStore {
    private static let positionsKey = "playback.positions.v2"
    private static let historyKey = "search.history"
    private static let maxHistory = 12
    private static let maxPositions = 300

    /// Position plus when it was written. The timestamp exists purely so the
    /// store can be pruned by recency; without it there is no way to tell an
    /// old entry from a new one, since the keys are opaque Easynews hashes.
    private struct Entry: Codable {
        var position: Double
        var updated: Double
    }

    // MARK: - Resume

    private static func loadEntries() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: positionsKey),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveEntries(_ entries: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: positionsKey)
    }

    /// Stored as a 0...1 fraction. Using a fraction rather than seconds means
    /// resume works without knowing the duration, which VLC only reports once
    /// it has parsed the container.
    static func resumePosition(for fileID: String) -> Float? {
        guard let entry = loadEntries()[fileID],
              entry.position > 0.02,
              entry.position < 0.95
        else { return nil }
        return Float(entry.position)
    }

    static func saveResumePosition(_ position: Float, for fileID: String) {
        var entries = loadEntries()

        // Barely started or essentially finished: forget it rather than
        // offering to resume 12 seconds in or during the credits.
        if position <= 0.02 || position >= 0.95 {
            entries.removeValue(forKey: fileID)
        } else {
            entries[fileID] = Entry(
                position: Double(position),
                updated: Date().timeIntervalSince1970
            )
        }

        // Drop the least recently watched. Sorting by key here would evict
        // arbitrary entries, since the keys are content hashes.
        if entries.count > maxPositions {
            let keep = entries
                .sorted { $0.value.updated > $1.value.updated }
                .prefix(maxPositions)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }

        saveEntries(entries)
    }

    // MARK: - Search history

    static var searchHistory: [String] {
        UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    static func recordSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var history = searchHistory.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        history.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(history.prefix(maxHistory)), forKey: historyKey)
    }

    static func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}
