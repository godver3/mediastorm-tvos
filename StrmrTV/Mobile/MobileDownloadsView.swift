#if os(iOS)
import SwiftUI

/// Downloads, as the Expo screen: storage used, the downloads still in progress, then the
/// finished movies and the shows (each a page of its seasons and episodes), sorted by the
/// toolbar's Sort menu. A tap plays a finished download (from the resume point the server
/// knows, when it answers) or pauses / resumes a running one; swipe to delete, Edit to delete
/// several. Needs no server connection: everything listed is on the device. Hosted inside the
/// caller's NavigationStack.
struct MobileDownloadsView: View {
    @ObservedObject private var manager = DownloadManager.shared
    @ObservedObject private var settings = DownloadSettings.shared
    @StateObject private var prompts = MobileDownloadsPrompts()
    @State private var selection: Set<String> = []
    @State private var editMode: EditMode = .inactive

    var body: some View {
        Group {
            if manager.items.isEmpty {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Movies and episodes you download can be watched without a connection. Download from a title’s page with More Options › Download.")
                }
            } else {
                list
            }
        }
        .navigationTitle("Downloads")
        .toolbar { toolbar }
        .environment(\.editMode, $editMode)
        .downloadPrompts(prompts) {
            selection = []
            editMode = .inactive
        }
        .task { await manager.deleteWatchedIfEnabled() }
        .onChange(of: manager.items.isEmpty) { _, empty in if empty { editMode = .inactive } }
    }

    // MARK: List

    private var list: some View {
        List(selection: $selection) {
            Section {
                MobileDownloadsStorage(used: manager.usedBytes)
            }
            let active = sorted(manager.items.filter { $0.status != .completed })
            if !active.isEmpty {
                Section("In Progress") {
                    ForEach(active) { item in row(item) }
                }
            }
            let movies = sorted(manager.completed.filter(\.isMovie))
            if !movies.isEmpty {
                Section("Movies") {
                    ForEach(movies) { item in row(item) }
                }
            }
            let shows = showGroups
            if !shows.isEmpty {
                Section("Shows") {
                    ForEach(shows, id: \.key) { show in
                        NavigationLink {
                            MobileDownloadsShowView(titleID: show.key, name: show.episodes[0].name)
                        } label: {
                            MobileDownloadShowRow(episodes: show.episodes)
                        }
                        .tag("show:" + show.key)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                prompts.confirmDelete(ids: show.episodes.map(\.id))
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: manager.items.map(\.id))
    }

    private func row(_ item: DownloadItem) -> some View {
        Button {
            MobileDownloadActions.primary(item) { prompts.play($0) }
        } label: {
            MobileDownloadRow(item: item)
                .overlay(alignment: .trailing) {
                    if prompts.checkingResume == item.id { ProgressView().padding(.trailing, 2) }
                }
        }
        .tint(.primary)
        .tag(item.id)
        .modifier(MobileDownloadRowActions(item: item, prompts: prompts))
    }

    /// Finished episodes by show, in the list's sort (a show sorts by its newest episode).
    private var showGroups: [(key: String, episodes: [DownloadItem])] {
        let episodes = manager.completed.filter(\.isEpisode)
        let groups = Dictionary(grouping: episodes, by: \.showKey)
        let ordered = sorted(groups.values.compactMap { $0.max { $0.createdAt < $1.createdAt } })
        return ordered.compactMap { latest in groups[latest.showKey].map { (latest.showKey, $0) } }
    }

    private func sorted(_ items: [DownloadItem]) -> [DownloadItem] {
        switch settings.sort {
        case .newest: items.sorted { $0.createdAt > $1.createdAt }
        case .oldest: items.sorted { $0.createdAt < $1.createdAt }
        case .nameAscending: items.sorted { Self.sortKey($0) < Self.sortKey($1) }
        case .nameDescending: items.sorted { Self.sortKey($0) > Self.sortKey($1) }
        }
    }

    private static func sortKey(_ item: DownloadItem) -> String {
        item.name.lowercased() + String(format: "%04d%04d", item.seasonNumber ?? 0, item.episodeNumber ?? 0)
    }

    /// The selection's download IDs (a selected show stands for all of its episodes).
    private var selectedIDs: [String] {
        selection.flatMap { tag -> [String] in
            guard tag.hasPrefix("show:") else { return [tag] }
            let key = String(tag.dropFirst(5))
            return manager.items.filter { $0.isEpisode && $0.status == .completed && $0.showKey == key }.map(\.id)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !manager.items.isEmpty {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if editMode.isEditing {
                Button(role: .destructive) { prompts.confirmDelete(ids: selectedIDs) } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
            } else {
                Menu {
                    Picker("Sort By", selection: $settings.sort) {
                        ForEach(DownloadSettings.Sort.allCases) { sort in Text(sort.label).tag(sort) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                NavigationLink { MobileDownloadSettingsView() } label: {
                    Label("Download Settings", systemImage: "gearshape")
                }
            }
        }
    }
}

/// Storage: what downloads take and what is left on the device, as a capacity gauge.
struct MobileDownloadsStorage: View {
    let used: Int64

    var body: some View {
        let free = DownloadStorage.availableBytes ?? 0
        let total = max(DownloadStorage.totalBytes ?? 0, 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Storage", systemImage: "internaldrive")
                Spacer()
                Text("\(DownloadFormat.bytes(used)) used").foregroundStyle(.secondary)
            }
            Gauge(value: Double(total - free), in: 0...Double(total)) {
                EmptyView()
            }
            .gaugeStyle(.linearCapacity)
            .tint(.accentColor)
            Text("\(DownloadFormat.bytes(free)) available on this \(UIDevice.current.localizedModel)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A show in the Downloads list: its poster, name and how many episodes are on the device.
struct MobileDownloadShowRow: View {
    let episodes: [DownloadItem]

    var body: some View {
        HStack(spacing: 12) {
            MobileDownloadPoster(item: episodes[0])
            VStack(alignment: .leading, spacing: 4) {
                Text(episodes[0].name).font(.body.weight(.semibold)).lineLimit(2)
                Text(episodes.count == 1 ? String(localized: "1 episode") : String(localized: "\(episodes.count) episodes"))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(DownloadFormat.bytes(episodes.reduce(0) { $0 + $1.expectedBytes }))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
