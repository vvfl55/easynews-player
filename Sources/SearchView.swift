import SwiftUI

struct SearchView: View {
    @EnvironmentObject var state: AppState
    @State private var inspecting: EasynewsFile?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Easynews")
                .searchable(text: $state.query, prompt: "Search Usenet for video")
                .onSubmit(of: .search) { state.search() }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            state.showingSettings = true
                        } label: {
                            Label("Account", systemImage: "person.crop.circle")
                        }
                    }
                }
        }
        .sheet(isPresented: $state.showingSettings) {
            SettingsView()
                .environmentObject(state)
        }
        .sheet(item: $inspecting) { file in
            RawJSONView(file: file)
        }
        .fullScreenCoverCompat(item: $state.playing) { request in
            PlayerScreen(request: request)
                .environmentObject(state)
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.isSearching && state.results.isEmpty {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !state.credentials.isConfigured {
            EmptyStateView(
                icon: "person.crop.circle.badge.questionmark",
                title: "Not signed in",
                message: "Add your Easynews username and password to start searching."
            )
        } else if state.results.isEmpty {
            EmptyStateView(
                icon: state.errorMessage == nil ? "magnifyingglass" : "exclamationmark.triangle",
                title: state.errorMessage == nil ? "Search Usenet" : "Nothing found",
                message: state.errorMessage ?? "Results stream directly — no download step."
            )
        } else {
            List(state.results) { file in
                ResultRow(file: file)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await state.play(file) }
                    }
                    .contextMenu {
                        Button("Inspect raw JSON") { inspecting = file }
                    }
            }
            .listStyle(.plain)
        }
    }
}

struct ResultRow: View {
    let file: EasynewsFile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.baseName)
                .font(.callout.weight(.medium))
                .lineLimit(2)

            HStack(spacing: 6) {
                if let res = file.resolutionLabel { Chip(text: res, tint: .blue) }
                Chip(text: file.ext.replacingOccurrences(of: ".", with: "").uppercased(), tint: .gray)
                Chip(text: file.sizeLabel, tint: .gray)
                if let runtime = file.runtime, !runtime.isEmpty {
                    Chip(text: runtime, tint: .gray)
                }
            }

            if !file.audioLanguages.isEmpty {
                Text("Audio: " + file.audioLanguages.prefix(4).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct Chip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(tint)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Easynews account")
                } footer: {
                    Text("Stored in the Keychain on this device and sent only to members.easynews.com.")
                }

                if state.credentials.isConfigured {
                    Section {
                        Button("Sign out", role: .destructive) {
                            state.signOut()
                            username = ""
                            password = ""
                        }
                    }
                }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        state.saveCredentials(
                            Credentials(username: username, password: password)
                        )
                        dismiss()
                    }
                    .disabled(username.isEmpty || password.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            username = state.credentials.username
            password = state.credentials.password
        }
        #if os(macOS)
        .frame(width: 420, height: 300)
        #endif
    }
}

// MARK: - Debug

/// Easynews shifts field names between API versions. If a row renders wrong,
/// long-press it and compare the raw object against EasynewsFile.from().
struct RawJSONView: View {
    let file: EasynewsFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(file.rawJSON)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Raw response")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 480)
        #endif
    }
}

// MARK: - Platform helpers

extension View {
    /// fullScreenCover doesn't exist on macOS; fall back to a sheet there.
    @ViewBuilder
    func fullScreenCoverCompat<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        self.sheet(item: item, content: content)
        #else
        self.fullScreenCover(item: item, content: content)
        #endif
    }
}
