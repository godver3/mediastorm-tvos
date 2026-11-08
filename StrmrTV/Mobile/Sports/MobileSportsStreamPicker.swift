#if os(iOS)
import SwiftUI

/// The stream picker on a phone, as a sheet (Expo `SportsStreamPicker`): the live channels that
/// look like they carry the event (`SportsStreamSearch`), strongest match first, a Stremio
/// channel expanding into its streams once looked up (`SportsStreamLookups`). Tapping one hands
/// it to the presenter, which closes the sheet and tunes it; a single strong match of a live
/// event plays at once (`SportsStreamOptions.autoPlay`). Search All Sources widens the search
/// past the admin's default sources.
struct MobileSportsStreamPicker: View {
    let target: SportsWatchTarget
    let onPick: (SportsStreamMatch) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var matches: [SportsStreamMatch] = []
    @State private var groups: [SportsStreamGroup] = []
    @State private var loading = true
    @State private var broad = false
    @State private var error: String?
    @State private var autoPlayWaiting = false
    @StateObject private var lookups = SportsStreamLookups()

    private var rows: [SportsStreamRow] { SportsStreamOptions.rows(matches, lookups: lookups.states) }

    var body: some View {
        NavigationStack {
            List {
                if loading || waitingOnLookup {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(broad ? "Searching all sources…" : "Searching channels…").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    if let error, rows.isEmpty {
                        ContentUnavailableView("No Streams Found", systemImage: "antenna.radiowaves.left.and.right.slash",
                                               description: Text(error))
                            .listRowBackground(Color.clear)
                    }
                    if !rows.isEmpty {
                        Section(subtitle) {
                            ForEach(rows) { row in
                                Button { play(row.match) } label: { MobileSportsStreamRow(row: row).contentShape(Rectangle()) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("sports-stream-\(row.match.channelId)"
                                        + (row.match.stremioStreamIndex.map { "-\($0)" } ?? ""))
                            }
                        }
                    }
                    if !broad {
                        Section {
                            Button { broad = true } label: { Label("Search All Sources", systemImage: "magnifyingglass") }
                                .accessibilityIdentifier("sports-search-all")
                        } footer: {
                            Text("Looks past the default sources set for this competition.")
                        }
                    }
                }
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: broad) {
            await search(broad: broad)
            await lookups.run(matches)
        }
        .onChange(of: lookups.states) { checkAutoPlay() }
    }

    private var subtitle: String {
        rows.count == 1 ? String(localized: "1 stream") : String(localized: "\(rows.count) streams")
    }

    private func search(broad: Bool) async {
        autoPlayWaiting = false
        loading = true
        defer { loading = false }
        do {
            let found = try await SportsStreamSearch.find(target, broad: broad)
            matches = found.matches
            groups = found.groups
            error = matches.isEmpty ? SportsStreamSearch.emptyMessage(target) : nil
            autoPlayWaiting = !broad
            checkAutoPlay()
        } catch {
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }

    private var waitingOnLookup: Bool {
        autoPlayWaiting && SportsStreamOptions.autoPlay(live: target.live, broad: broad, groups: groups,
                                                         lookups: lookups.states) == .wait
    }

    private func checkAutoPlay() {
        guard autoPlayWaiting else { return }
        switch SportsStreamOptions.autoPlay(live: target.live, broad: broad, groups: groups, lookups: lookups.states) {
        case .wait: return
        case .none: autoPlayWaiting = false
        case let .play(match):
            autoPlayWaiting = false
            play(match)
        }
    }

    private func play(_ match: SportsStreamMatch) {
        autoPlayWaiting = false
        onPick(match)
    }
}

/// A stream: the channel's logo, title and source line, and how sure the match is.
private struct MobileSportsStreamRow: View {
    let row: SportsStreamRow

    var body: some View {
        let match = row.match
        HStack(spacing: 12) {
            RemoteImage(url: match.channel.logoURL, size: CGSize(width: 56, height: 32), contentMode: .fit) { _ in
                Image(systemName: "tv").foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                let details = SportsStreamSearch.details(match)
                Text(row.loading ? [details, String(localized: "Loading streams…")].filter { !$0.isEmpty }.joined(separator: " · ")
                     : details)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(match.isStrong ? "Strong" : "Possible")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(match.isStrong ? Color.green.opacity(0.18) : Color(.tertiarySystemFill)))
                .foregroundStyle(match.isStrong ? Color.green : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
