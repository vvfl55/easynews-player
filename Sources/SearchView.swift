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
                        Menu {
                            Picker("Sort", selection: $state.sort) {
                                ForEach(SortOption.allCases) { option in
                                    Label(option.label, systemImage: option.systemImage)
                                        .tag(option)
                                }
                            }
                            Divider()
                            Button {
                                state.showingSettings = true
                            } label: {
                                Label("Account", systemImage: "person.crop.circle")
                            }
                        } label: {
                            Label("Options", systemImage: "ellipsis.circle")
                        }
                        .accessibilityLabel("Options")
                    }
                }
        }
        .sheet(isPresented: $state.showingSettings) {
            SettingsView().environmentObject(state)
        }
        .sheet(item: $inspecting) { file in
            RawJSONView(file: file)
        }
        .fullScreenCoverCompat(item: $state.playing) { request in
            PlayerScreen(request: request).environmentObject(state)
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
            idleState
        } else {
            resultsList
        }
    }

    /// Before any search, offer recent terms rather than a bare empty screen.
    @ViewBuilder
    private var idleState: some View {
        if state.history.isEmpty || state.errorMessage != nil {
            EmptyStateView(
                icon: state.errorMessage == nil ? "magnifyingglass" : "exclamationmark.triangle",
                title: state.errorMessage == nil ? "Search Usenet" : "Nothing found",
                message: state.errorMessage ?? "Results stream directly — no download step."
            )
        } else {
            List {
                Section {
                    ForEach(state.history, id: \.self) { term in
                        Button {
                            state.searchAgain(term)
                        } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("Recent searches")
                } footer: {
                    Button("Clear", role: .destructive) { state.clearHistory() }
                        .font(.caption)
                }
            }
        }
    }

    private var resultsList: some View {
        List {
            ForEach(state.results) { file in
                ResultRow(file: file)
                    .contentShape(Rectangle())
                    .onTapGesture { Task { await state.play(file) } }
                    .onAppear { state.loadMoreIfNeeded(currentItem: file) }
                    .contextMenu { rowMenu(for: file) }
            }

            if state.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func rowMenu(for file: EasynewsFile) -> some View {
        Button {
            Task { await state.play(file) }
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        ForEach(ExternalPlayer.allCases) { target in
            Button {
                Task {
                    if let url = await state.externalPlayerURL(for: file, scheme: target) {
                        openExternal(url)
                    }
                }
            } label: {
                Label("Open in \(target.rawValue)", systemImage: "arrow.up.forward.app")
            }
        }

        Divider()

        Button {
            inspecting = file
        } label: {
            Label("Inspect raw JSON", systemImage: "curlybraces")
        }
    }

    private func openExternal(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
}

#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ResultRow: View {
    let file: EasynewsFile

    private var resumeFraction: Float? { PlaybackStore.resumePosition(for: file.id) }

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
                if !file.subtitleLanguages.isEmpty {
                    Chip(text: "CC", tint: .green)
                }
            }

            if !file.audioLanguages.isEmpty {
                Text("Audio: " + file.audioLanguages.prefix(4).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // A thin progress bar is a quieter "you were here" than a badge.
            if let fraction = resumeFraction {
                ProgressView(value: Double(fraction))
                    .progressViewStyle(.linear)
                    .tint(.orange)
                    .frame(height: 2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(file.baseName)
        .accessibilityHint("Double tap to play")
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
                        state.saveCredentials(Credentials(username: username, password: password))
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
