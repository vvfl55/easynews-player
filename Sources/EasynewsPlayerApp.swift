import SwiftUI

@main
struct EasynewsPlayerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            SearchView()
                .environmentObject(state)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 650)
        #endif
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var credentials: Credentials
    @Published var query = ""
    @Published var results: [EasynewsFile] = []
    @Published var isSearching = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var showingSettings = false
    @Published var playing: PlaybackRequest?
    @Published var sort: SortOption = .relevance {
        didSet { if oldValue != sort, !results.isEmpty { search() } }
    }
    @Published var history: [String] = PlaybackStore.searchHistory

    private let client = EasynewsClient()
    private var searchTask: Task<Void, Never>?
    private var currentPage = 1
    private var canLoadMore = false
    private var lastSearchedTerm = ""

    init() {
        credentials = CredentialStore.load()
        showingSettings = !credentials.isConfigured
    }

    func saveCredentials(_ new: Credentials) {
        credentials = new
        CredentialStore.save(new)
    }

    func signOut() {
        CredentialStore.clear()
        credentials = .empty
        results = []
        errorMessage = nil
        showingSettings = true
    }

    // MARK: - Searching

    func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        searchTask?.cancel()
        errorMessage = nil
        isSearching = true
        currentPage = 1
        canLoadMore = false
        lastSearchedTerm = term

        let creds = credentials
        let sortOption = sort

        searchTask = Task {
            // defer guarantees the spinner clears on every exit path,
            // including cancellation. Without it a cancelled search left
            // the UI spinning forever.
            defer { isSearching = false }

            do {
                let page = try await client.search(
                    query: term, page: 1, sort: sortOption, credentials: creds
                )
                guard !Task.isCancelled else { return }

                results = page.files
                canLoadMore = page.hasMore
                PlaybackStore.recordSearch(term)
                history = PlaybackStore.searchHistory

                if page.files.isEmpty {
                    errorMessage = "No video files matched \"\(term)\"."
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = error.localizedDescription
            }
        }
    }

    func searchAgain(_ term: String) {
        query = term
        search()
    }

    /// Called when the last visible row appears. Easynews caps a page at 250,
    /// so anything beyond that needs an explicit next-page fetch.
    func loadMoreIfNeeded(currentItem: EasynewsFile) {
        guard canLoadMore,
              !isLoadingMore,
              !isSearching,
              results.suffix(10).contains(where: { $0.id == currentItem.id })
        else { return }

        isLoadingMore = true
        let nextPage = currentPage + 1
        let creds = credentials
        let sortOption = sort
        let term = lastSearchedTerm

        Task {
            defer { isLoadingMore = false }
            do {
                let page = try await client.search(
                    query: term, page: nextPage, sort: sortOption, credentials: creds
                )
                guard !Task.isCancelled else { return }

                // Guard against duplicates if Easynews repeats rows across pages.
                let known = Set(results.map(\.id))
                let fresh = page.files.filter { !known.contains($0.id) }

                results.append(contentsOf: fresh)
                currentPage = nextPage
                canLoadMore = page.hasMore && !fresh.isEmpty
            } catch {
                // A failed page-2 fetch shouldn't blow away page 1.
                canLoadMore = false
            }
        }
    }

    func clearHistory() {
        PlaybackStore.clearHistory()
        history = []
    }

    // MARK: - Playback

    func play(_ file: EasynewsFile) async {
        guard let url = await client.streamURL(for: file, credentials: credentials) else {
            errorMessage = "Couldn't build a stream URL. Run the search again and retry."
            return
        }
        playing = PlaybackRequest(
            file: file,
            url: url,
            resumeAt: PlaybackStore.resumePosition(for: file.id)
        )
    }

    /// Hand off to VLC or Infuse if they're installed. Useful as an escape
    /// hatch for a file the embedded player struggles with.
    func externalPlayerURL(for file: EasynewsFile, scheme: ExternalPlayer) async -> URL? {
        guard let stream = await client.streamURL(for: file, credentials: credentials) else { return nil }
        return scheme.url(for: stream)
    }
}

enum ExternalPlayer: String, CaseIterable, Identifiable {
    case vlc = "VLC"
    case infuse = "Infuse"

    var id: String { rawValue }

    func url(for stream: URL) -> URL? {
        let encoded = stream.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        switch self {
        case .vlc:
            return URL(string: "vlc-x-callback://x-callback-url/stream?url=\(encoded)")
        case .infuse:
            return URL(string: "infuse://x-callback-url/play?url=\(encoded)")
        }
    }
}

struct PlaybackRequest: Identifiable {
    let file: EasynewsFile
    let url: URL
    let resumeAt: Float?
    var id: String { file.id }
}
