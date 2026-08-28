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
    @Published var errorMessage: String?
    @Published var hasSearched = false
    @Published var showingSettings = false
    @Published var playing: PlaybackRequest?

    private let client = EasynewsClient()
    private var searchTask: Task<Void, Never>?

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
        hasSearched = false
        showingSettings = true
    }

    func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        searchTask?.cancel()
        errorMessage = nil
        isSearching = true

        let creds = credentials
        searchTask = Task {
            do {
                let found = try await client.search(query: term, credentials: creds)
                guard !Task.isCancelled else { return }
                results = found
                hasSearched = true
                if found.isEmpty {
                    errorMessage = "No video files matched \"\(term)\"."
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                hasSearched = true
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    func play(_ file: EasynewsFile) async {
        guard let url = await client.streamURL(for: file, credentials: credentials) else {
            errorMessage = "Couldn't build a stream URL for that file. Run a new search and try again."
            return
        }
        playing = PlaybackRequest(file: file, url: url)
    }
}

struct PlaybackRequest: Identifiable {
    let file: EasynewsFile
    let url: URL
    var id: String { file.id }
}
