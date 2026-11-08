#if os(iOS)
import SwiftUI

/// Choose Source as a sheet: the title's library copies, then the indexer / scraper results in
/// the server's order with their health (pending checks long-polled), as the TV's
/// `SourcePickerView`. Tap plays a source; its menu (long press, or the row's swipe) opens
/// Audio & Subtitles to probe it and pick tracks first. Searches through the shared
/// `SourceSearch`, so the player's Switch Source shows the same list.
struct MobileSourcePicker: View {
    let title: DetailsTarget
    let episode: Episode?
    let heading: String
    var libraryVersions: [LibraryVersion] = []
    let contentPreference: ContentPreference?
    var onPickLibrary: (LibraryVersion) -> Void = { _ in }
    let onPick: (SourceResult, ManualTrackPick?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var results: [SourceResult] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var health: [Int: SourceHealth] = [:]
    @State private var trackPreferences = ManualTrackPreferences()
    @State private var trackOverrides: [Int: ManualTrackOverrides] = [:]
    @State private var probes: [Int: SourceTrackProbe] = [:]
    @State private var tracksTarget: TracksTarget?

    struct TracksTarget: Identifiable, Hashable {
        let result: SourceResult
        var id: Int { result.index }
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !libraryVersions.isEmpty {
                    Section(libraryVersions.count == 1 ? String(localized: "In your libraries")
                                                       : String(localized: "\(libraryVersions.count) in your libraries")) {
                        ForEach(libraryVersions) { version in
                            Button {
                                dismiss()
                                onPickLibrary(version)
                            } label: {
                                LibraryVersionRow(version: version)
                            }
                            .tint(.primary)
                        }
                    }
                }
                streams
            }
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(item: $tracksTarget) { target in tracksPage(target.result) }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var streams: some View {
        Section {
            if isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Searching sources…").foregroundStyle(.secondary)
                }
            } else if let error {
                ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else if results.isEmpty {
                ContentUnavailableView("No Sources Found", systemImage: "magnifyingglass")
            } else {
                ForEach(results, id: \.index) { result in
                    Button {
                        dismiss()
                        onPick(result, pick(for: result))
                    } label: {
                        SourceRow(result: result, health: health[result.index],
                                  hasTrackPicks: !(trackOverrides[result.index]?.isEmpty ?? true))
                    }
                    .tint(.primary)
                    .contextMenu {
                        Button {
                            dismiss()
                            onPick(result, pick(for: result))
                        } label: { Label("Play", systemImage: "play.fill") }
                        Button { showTracks(result) } label: { Label("Audio & Subtitles…", systemImage: "waveform") }
                    }
                    .swipeActions(edge: .trailing) {
                        Button { showTracks(result) } label: { Label("Tracks", systemImage: "waveform") }
                            .tint(.indigo)
                    }
                }
            }
        } header: {
            if !libraryVersions.isEmpty || (!isLoading && !results.isEmpty) {
                Text(results.isEmpty ? String(localized: "Streams")
                                     : results.count == 1 ? String(localized: "1 source")
                                                          : String(localized: "\(results.count) sources"))
            }
        }
    }

    private func tracksPage(_ result: SourceResult) -> some View {
        let index = result.index
        let close = dismiss
        return MobileTracksView(
            model: SourceTracksModel(result: result, cached: probes[index]) { probe in record(probe, for: result) },
            defaults: nil, preferences: trackPreferences,
            overrides: Binding(get: { trackOverrides[index] ?? ManualTrackOverrides() },
                               set: { trackOverrides[index] = $0 }),
            playLabel: String(localized: "Play"), inSheet: false
        ) { pick in
            close()
            onPick(result, pick)
        }
    }

    // MARK: Tracks

    private func showTracks(_ result: SourceResult) {
        SourceTracksModel.log.notice("tracks: \(result.serviceType) \"\(result.title)\" (cached probe \(probes[result.index] != nil))")
        tracksTarget = TracksTarget(result: result)
    }

    private func record(_ probe: SourceTrackProbe, for result: SourceResult) {
        if !probe.audio.isEmpty || !probe.subtitles.isEmpty { probes[result.index] = probe }
        let debrid = result.serviceType.lowercased() == "debrid"
        let state = probe.playable ? (debrid ? "cached" : "healthy") : (debrid ? "not_cached" : "unhealthy")
        setHealth(SourceHealth(state: state, token: nil), at: result.index)
    }

    private func pick(for result: SourceResult) -> ManualTrackPick? {
        guard let overrides = trackOverrides[result.index], !overrides.isEmpty,
              let probe = probes[result.index] else { return nil }
        return ManualTrackPick(overrides: overrides, audio: probe.audio, subtitles: probe.subtitles)
    }

    // MARK: Search and health

    private var query: String {
        SourceSearch.query(name: title.name, year: title.year,
                           episode: episode.map { ($0.seasonNumber, $0.episodeNumber) })
    }

    private func setHealth(_ value: SourceHealth, at index: Int) {
        health[index] = value
        SourceSearch.updateHealth(title: title, query: query, numbering: episode?.numbering, index: index, health: value)
    }

    private func load() async {
        Task { trackPreferences = await ManualTrackPreferences.current(content: contentPreference) }
        do {
            results = try await SourceSearch.search(title: title, query: query, numbering: episode?.numbering)
            health = SourceSearch.initialHealth(results)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        let tokens = Set(health.values.filter { $0.state == "pending" }.compactMap(\.token))
        for token in tokens {
            var complete = false
            while !complete, !Task.isCancelled {
                guard let snapshot = try? await APIClient.shared.sourceHealth(token: token) else { break }
                for entry in snapshot.results { setHealth(entry.health, at: entry.index) }
                complete = snapshot.complete
            }
        }
        if !Task.isCancelled {
            for (index, h) in health where h.state == "pending" { setHealth(SourceHealth(state: "unknown", token: nil), at: index) }
        }
    }
}
#endif
