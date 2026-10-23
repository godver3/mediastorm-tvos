import SwiftUI

/// Full-screen list of the backend's indexer / scraper results for one movie or episode.
struct SourcePickerView: View {
    let title: DetailsTarget
    let episode: Episode?
    /// The title's per-title track languages, for the defaults a long press shows.
    let contentPreference: ContentPreference?
    /// The source, with the track picks made for it this visit (nil = the server's choice).
    let onPick: (SourceResult, ManualTrackPick?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var results: [SourceResult] = []
    @State private var isLoading = true
    @State private var error: String?
    /// Health / cache state by result index; pending rows are updated by the long-poll.
    @State private var health: [Int: SourceHealth] = [:]
    @State private var trackPreferences = ManualTrackPreferences()
    /// Track picks and probes by result index, kept for the visit (Expo `trackOverrides`).
    @State private var trackOverrides: [Int: ManualTrackOverrides] = [:]
    @State private var probes: [Int: SourceTrackProbe] = [:]
    /// The result whose tracks are shown (long press).
    @State private var tracksTarget: TracksTarget?
    /// A long press's release can also arrive as a Select; it is ignored until then.
    @State private var suppressSelectUntil = Date.distantPast

    struct TracksTarget: Identifiable {
        let result: SourceResult
        var id: Int { result.index }
    }

    private var heading: String {
        guard let episode else { return title.name }
        return "\(title.name) · \(episode.code)"
    }

    var body: some View {
        // A plain scroll view of focusable rows: focus moving down scrolls it, so every
        // result is reachable with the remote.
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(heading).font(.title2.weight(.semibold))
                    if !isLoading, error == nil, !results.isEmpty {
                        Text(results.count == 1 ? "1 source" : "\(results.count) sources")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 24)

                if isLoading {
                    HStack(spacing: 24) {
                        ProgressView()
                        Text("Searching sources…").foregroundStyle(.secondary)
                    }
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                } else if results.isEmpty {
                    Text("No sources found").foregroundStyle(.secondary)
                } else {
                    ForEach(results, id: \.index) { result in
                        Button {
                            guard Date() >= suppressSelectUntil else { return }
                            dismiss()
                            onPick(result, pick(for: result))
                        } label: {
                            SourceRow(result: result, health: health[result.index],
                                      hasTrackPicks: !(trackOverrides[result.index]?.isEmpty ?? true))
                        }
                        .buttonStyle(SourceRowStyle())
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            showTracks(result)
                        })
                    }
                }
            }
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        }
        .scrollClipDisabled()
        .background { SourcePickerBackdrop(url: title.backdropURL) }
        .onExitCommand { dismiss() }
        .task { await load() }
        .fullScreenCover(item: $tracksTarget) { target in
            let index = target.result.index
            SourceTracksView(
                result: target.result, cached: probes[index],
                onProbe: { probe in record(probe, for: target.result) },
                backdropURL: title.backdropURL, preferences: trackPreferences,
                overrides: Binding(get: { trackOverrides[index] ?? ManualTrackOverrides() },
                                   set: { trackOverrides[index] = $0 })
            ) { pick in
                // Leave the track page, then the picker, then play.
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    dismiss()
                    onPick(target.result, pick)
                }
            }
        }
    }

    // MARK: Tracks

    /// Long press: probe the source and list its tracks (the Expo TV track modal).
    private func showTracks(_ result: SourceResult) {
        suppressSelectUntil = Date().addingTimeInterval(1.5)
        SourceTracksModel.log.notice("long press: \(result.serviceType) \"\(result.title)\" (cached probe \(probes[result.index] != nil))")
        tracksTarget = TracksTarget(result: result)
    }

    /// Keeps a probe with tracks for the visit and shows its outcome on the row.
    private func record(_ probe: SourceTrackProbe, for result: SourceResult) {
        if !probe.audio.isEmpty || !probe.subtitles.isEmpty { probes[result.index] = probe }
        let debrid = result.serviceType.lowercased() == "debrid"
        let state = probe.playable ? (debrid ? "cached" : "healthy") : (debrid ? "not_cached" : "unhealthy")
        health[result.index] = SourceHealth(state: state, token: nil)
        SourceSearch.updateHealth(title: title, query: query, index: result.index, health: SourceHealth(state: state, token: nil))
    }

    /// The picks made for `result` this visit, which a plain Select also plays with (as Expo).
    private func pick(for result: SourceResult) -> ManualTrackPick? {
        guard let overrides = trackOverrides[result.index], !overrides.isEmpty,
              let probe = probes[result.index] else { return nil }
        return ManualTrackPick(overrides: overrides, audio: probe.audio, subtitles: probe.subtitles)
    }

    /// The search query, shared with the player's Switch Source (`SourceSearch`).
    private var query: String {
        SourceSearch.query(name: title.name, year: title.year,
                           episode: episode.map { ($0.seasonNumber, $0.episodeNumber) })
    }

    private func load() async {
        Task { trackPreferences = await ManualTrackPreferences.current(content: contentPreference) }
        do {
            // Kept for Switch Source, which shows these in the same order.
            results = try await SourceSearch.search(title: title, query: query)
            health = SourceSearch.initialHealth(results)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        await resolvePendingHealth()
    }

    /// Long-polls each pending check until it completes, applying results by index.
    private func resolvePendingHealth() async {
        let tokens = Set(health.values.filter { $0.state == "pending" }.compactMap(\.token))
        for token in tokens {
            var complete = false
            while !complete, !Task.isCancelled {
                guard let snapshot = try? await APIClient.shared.sourceHealth(token: token) else { break }
                for entry in snapshot.results {
                    health[entry.index] = entry.health
                    SourceSearch.updateHealth(title: title, query: query, index: entry.index, health: entry.health)
                }
                complete = snapshot.complete
            }
        }
        // Anything still pending (poll failed or token expired) stops spinning.
        if !Task.isCancelled {
            for (index, h) in health where h.state == "pending" {
                health[index] = SourceHealth(state: "unknown", token: nil)
                SourceSearch.updateHealth(title: title, query: query, index: index, health: SourceHealth(state: "unknown", token: nil))
            }
        }
    }
}

/// Full-width row that highlights on focus, like a grouped list row (also the subtitle search list).
struct SourceRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isFocused ? Color.white : Color.white.opacity(0.08))
                )
                .scaleEffect(configuration.isPressed ? 0.99 : isFocused ? 1.02 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 18, y: 10)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
