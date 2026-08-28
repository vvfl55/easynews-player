import Foundation

/// Small amounts of persistent state: where you stopped watching, and what
/// you searched for. Both are tiny and disposable, so UserDefaults is the
/// right tool; nothing here justifies a database.
enum PlaybackStore {
    private static let positionsKey = "playback.positions"
    private static let historyKey = "search.history"
    private static let maxHistory = 12
    private static let maxPositions = 300

    // MARK: - Resume

    /// Stored as a 0...1 fraction keyed by the Easynews file hash. Using a
    /// fraction rather than seconds means resume works without knowing the
    /// duration, which VLC only reports after it has parsed the container.
    static func resumePosition(for fileID: String) -> Float? {
        let all = (UserDefaults.standard.dictionary(forKey: positionsKey) as? [String: Double]) ?? [:]
        guard let stored = all[fileID], stored > 0.02, stored < 0.95 else { return nil }
        return Float(stored)
    }

    static func saveResumePosition(_ position: Float, for fileID: String) {
        var all = (UserDefaults.standard.dictionary(forKey: positionsKey) as? [String: Double]) ?? [:]

        // Barely started or essentially finished: forget it rather than
        // offering to resume 12 seconds in or during the credits.
        if position <= 0.02 || position >= 0.95 {
            all.removeValue(forKey: fileID)
        } else {
            all[fileID] = Double(position)
        }

        if all.count > maxPositions {
            all = Dictionary(uniqueKeysWithValues: all.sorted { $0.key < $1.key }.suffix(maxPositions))
        }
        UserDefaults.standard.set(all, forKey: positionsKey)
    }

    static func hasResume(for fileID: String) -> Bool {
        resumePosition(for: fileID) != nil
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
