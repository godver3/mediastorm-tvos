#if os(iOS)
import SwiftUI

/// The phone's Live tab (Expo's `NewLiveScreen` on a phone): a channel list with what is on now,
/// or (when the server has guide data) a scrolling time grid, switched with a segmented control.
/// The toolbar holds the filter (All, Favorites, categories), the source and a menu with hidden
/// channels, refresh and Recordings; search filters on the server. Tapping a channel tunes it
/// in the shared live player (`LivePlayback`, as the TV's Live tab); swipe or long-press for
/// favorite / hide, recording and programme info.
struct MobileLiveView: View {
    @StateObject private var store = LiveStore()
    @AppStorage("live.mobile.mode") private var mode: LiveMode = .channels
    /// Moves progress bars and the guide's now line along.
    @State private var now = Date()
    /// The programme info sheet.
    @State private var info: MobileLiveInfoTarget?
    /// Run once a sheet is gone: the player can't come up while one is still dismissing.
    @State private var afterDismiss: (() -> Void)?
    /// The channel with the stream picked under Choose Source, tuned once the list has closed.
    @State private var chosenSource: LiveChannel?
    @State private var showsRecordings = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var showsGuide: Bool { mode == .guide && store.epgEnabled == true }

    var body: some View {
        content
            .navigationTitle("Live TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .searchable(text: Binding(get: { store.searchText }, set: { store.setSearchText($0) }),
                        // A phone on its side keeps its few rows for channels: the field shows on a pull.
                        placement: .navigationBarDrawer(displayMode: verticalSizeClass == .compact ? .automatic : .always), prompt: "Search Channels")
            .safeAreaInset(edge: .bottom) { noticeBar }
            .environmentObject(store)
            .environment(\.mobileLiveActions, MobileLiveActions(showInfo: { info = $0 }))
            .navigationDestination(isPresented: $showsRecordings) { MobileRecordingsView() }
            .sheet(item: $info, onDismiss: runAfterDismiss) { target in
                MobileLiveProgramSheet(target: target) { action in
                    afterDismiss = action
                    info = nil
                }
                .environmentObject(store)
            }
            .sheet(item: $store.sourceChoice, onDismiss: tuneChosenSource) { choice in
                MobileLiveSourceChoiceSheet(choice: choice) { stream in
                    chosenSource = choice.channel(streamIndex: stream.index)
                    store.sourceChoice = nil
                }
            }
            // The first run loads favorites and the EPG status, then every filter change reloads.
            .task(id: store.query) { await store.start() }
            .task { await store.pollRecordings() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    now = Date()
                }
            }
    }

    @ViewBuilder private var content: some View {
        if !store.visibleChannels.isEmpty {
            if showsGuide {
                MobileGuideView(now: now)
            } else {
                MobileChannelList(now: now)
            }
        } else if let error = store.loadError {
            ContentUnavailableView {
                Label("Couldn't Load Channels", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await store.reload(force: true) } }
                if store.filter != .all { Button("Show All Channels") { store.filter = .all } }
            }
        } else if store.total != nil, !store.isLoading {
            emptyState
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !store.search.isEmpty {
            ContentUnavailableView.search(text: store.search)
        } else if store.filter == .favorites {
            ContentUnavailableView("No Favorite Channels", systemImage: "star",
                                   description: Text("Swipe right on a channel, or long-press it, to add it to your favorites."))
        } else {
            ContentUnavailableView("No Channels", systemImage: "tv",
                                   description: Text("Add a Live TV source on the server to watch channels here."))
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if store.epgEnabled == true {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    Text("Channels").tag(LiveMode.channels)
                    Text("Guide").tag(LiveMode.guide)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("live.mode")
            }
        }
        ToolbarItem(placement: .topBarLeading) { filterMenu }
        ToolbarItem(placement: .topBarTrailing) { moreMenu }
    }

    /// All Channels and Favorites pick and close; categories toggle with the menu left open.
    private var filterMenu: some View {
        Menu {
            Button {
                store.filter = .all
            } label: {
                Label("All Channels", systemImage: store.filter == .all ? "checkmark" : "tv")
            }
            Button {
                store.filter = .favorites
            } label: {
                Label("Favorites", systemImage: store.filter == .favorites ? "checkmark" : "star")
            }
            if !store.categories.isEmpty {
                Section("Categories") {
                    ForEach(store.categories, id: \.self) { name in
                        Button {
                            store.toggleCategory(name)
                        } label: {
                            if store.filter.categories.contains(name) { Label(name, systemImage: "checkmark") } else { Text(name) }
                        }
                        .menuActionDismissBehavior(.disabled)
                    }
                }
            }
            if store.sources.count > 1 {
                Picker(selection: $store.sourceID) {
                    Text("All Sources").tag(String?.none)
                    ForEach(store.sources) { Text($0.name).tag(Optional($0.id)) }
                } label: {
                    Label("Source", systemImage: "antenna.radiowaves.left.and.right")
                }
                .pickerStyle(.menu)
            }
        } label: {
            Label(store.filter.label, systemImage: filterActive
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("live.filterMenu")
    }

    private var filterActive: Bool { store.filter != .all || store.sourceID != nil }

    private var moreMenu: some View {
        Menu {
            if let total = store.total {
                Section("\(total) channels") {}
            }
            Toggle(isOn: $store.showHidden) {
                Label("Show Hidden Channels", systemImage: "eye.slash")
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Label(store.epgEnabled == true ? "Refresh Guide & Channels" : "Refresh Channels",
                      systemImage: "arrow.clockwise")
            }
            Divider()
            Button {
                showsRecordings = true
            } label: {
                Label("Recordings", systemImage: "record.circle")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("live.moreMenu")
    }

    @ViewBuilder private var noticeBar: some View {
        if let text = store.actionError ?? store.notice {
            Text(text)
                .font(.footnote)
                .foregroundStyle(store.actionError != nil ? .red : .primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Playback after a sheet

    private func runAfterDismiss() {
        let action = afterDismiss
        afterDismiss = nil
        action?()
    }

    private func tuneChosenSource() {
        guard let channel = chosenSource else { return }
        chosenSource = nil
        LivePlayback.play(channel, program: store.current(channel, at: Date()))
    }
}

/// What the programme info sheet shows: a channel, and the programme tapped in the guide (else
/// the one on now).
struct MobileLiveInfoTarget: Identifiable {
    let channel: LiveChannel
    let program: EPGProgram?

    var id: String { "\(channel.id)|\(program?.start.timeIntervalSince1970 ?? 0)" }
}

/// Actions the list and guide rows hand back to the Live screen.
struct MobileLiveActions {
    var showInfo: (MobileLiveInfoTarget) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var mobileLiveActions = MobileLiveActions()
}

/// Plays `program` from the provider's archive when it has ended, else tunes the channel live.
@MainActor
enum MobileLiveTune {
    static func play(_ channel: LiveChannel, program: EPGProgram?) {
        let now = Date()
        if let program, program.stop <= now, channel.canReplay(program, now: now) {
            CatchupPlayback.play(channel, program: program)
        } else {
            LivePlayback.play(channel, program: program?.isAiring(at: now) == true ? program : nil)
        }
    }
}
#endif
