import SwiftUI

enum LiveMode: String, CaseIterable {
    case guide, channels
}

/// The Live tab: the channel guide (when the server has EPG data) or a grid of channel
/// cards, under one row of filters: a Favorites star, Favorites or a category, the source,
/// and search.
struct LiveView: View {
    /// Set when the view picks a channel for multiscreen instead of playing it.
    var picker: LivePicker?
    @StateObject private var store = LiveStore()
    @AppStorage("live.mode") private var mode: LiveMode = .guide
    /// Moves progress bars and the guide's now line along.
    @State private var now = Date()
    /// The control focused in the row above the guide or grid.
    @FocusState private var controlFocus: LiveControl?
    /// The control focus last left the row from: up from the guide or grid, and Menu
    /// inside them, go back to it rather than to whichever control sits above the cell.
    @State private var lastControl: LiveControl = .filter
    /// Where focus should land back in the guide or grid (see `LiveContentFocus`).
    @State private var contentFocus: LiveContentFocus?
    /// The More menu's Recordings (the Expo Live drawer's Recordings action), pushed over Live.
    @State private var showsRecordings = false

    private var showsGuide: Bool { mode == .guide && store.epgEnabled == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let picker {
                Text(picker.title).font(.title3.weight(.bold)).padding(.horizontal, CardGridLayout.inset)
            }
            LiveControls(store: store, mode: $mode, focus: $controlFocus, picking: picker != nil) { showsRecordings = true }
                .defaultFocus($controlFocus, lastControl, priority: .userInitiated)
                .padding(.horizontal, CardGridLayout.inset)
                .onMoveCommand { if $0 == .down { contentFocus = .enter } }
                .onChange(of: controlFocus) { _, new in if let new { lastControl = new } }
            if let error = store.actionError ?? picker?.error {
                Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal, CardGridLayout.inset)
            }
            content
        }
        // Pinned to the top, so the controls don't sit mid-screen while the list loads.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environmentObject(store)
        .environment(\.liveChannelPick, picker?.onPick)
        .environment(\.livePlayingChannelID, picker?.playingChannelID)
        // In the picker, Menu on the controls closes it (in the guide or grid it moves up first).
        .onExitCommand(perform: picker?.onClose)
        .navigationDestination(isPresented: $showsRecordings) { RecordingsView().pinsSideMenu() }
        // The first run loads favorites and the EPG status, then every filter change reloads.
        .task(id: store.query) { await store.start() }
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
                LiveGuideView(now: now, request: $contentFocus, onExit: { controlFocus = lastControl })
            } else {
                LiveChannelGrid(now: now, request: $contentFocus, onExit: { controlFocus = lastControl })
            }
        } else if let error = store.loadError {
            GridMessage(text: error)
        } else if store.total != nil, !store.isLoading {
            GridMessage(text: emptyMessage)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 100)
        }
    }

    private var emptyMessage: String {
        if !store.search.isEmpty { return String(localized: "No channels match “\(store.search)”.") }
        if store.filter == .favorites { return String(localized: "No favorite channels yet. Long press a channel to add it.") }
        return String(localized: "No channels.")
    }
}

enum LiveControl: Hashable {
    case view, filter, favorites, source, search, more
}

/// View switch, channel filter, source, search and a menu with the rest.
private struct LiveControls: View {
    @ObservedObject var store: LiveStore
    @Binding var mode: LiveMode
    var focus: FocusState<LiveControl?>.Binding
    /// In the multiscreen picker: no Recordings or Multiscreen.
    let picking: Bool
    let openRecordings: () -> Void
    @ObservedObject private var resume = MultiscreenResume.shared

    var body: some View {
        HStack(spacing: 24) {
            // A menu, as Movies / Shows on the Lists tab: a segmented picker switches on focus.
            if store.epgEnabled == true {
                Menu {
                    Picker("View", selection: $mode) {
                        Label("Guide", systemImage: "calendar").tag(LiveMode.guide)
                        Label("Channels", systemImage: "square.grid.3x2").tag(LiveMode.channels)
                    }
                } label: {
                    Label(mode == .guide ? "Guide" : "Channels", systemImage: "chevron.up.chevron.down")
                }
                .fixedSize()
                .focused(focus, equals: .view)
                .accessibilityIdentifier("live.viewMenu")
            }
            Picker(selection: $store.filter) {
                Label("All Channels", systemImage: "tv").tag(LiveFilter.all)
                Label("Favorites", systemImage: "star").tag(LiveFilter.favorites)
                if !store.categories.isEmpty {
                    Section("Categories") {
                        ForEach(store.categories, id: \.self) { Text($0).tag(LiveFilter.category($0)) }
                    }
                }
            } label: {
                Label(store.filter.label, systemImage: store.filter == .favorites ? "star.fill" : "line.3.horizontal.decrease")
            }
            .pickerStyle(.menu)
            .fixedSize()
            .focused(focus, equals: .filter)
            .accessibilityIdentifier("live.filterMenu")
            Button {
                store.toggleFavoritesOnly()
            } label: {
                Label("Favorites", systemImage: store.filter == .favorites ? "star.fill" : "star")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(store.filter == .favorites ? .yellow : .primary)
            }
            .accessibilityLabel(store.filter == .favorites ? "Show All Channels" : "Show Favorites Only")
            .focused(focus, equals: .favorites)
            .accessibilityIdentifier("live.favoritesToggle")
            if store.sources.count > 1 {
                Picker(selection: $store.sourceID) {
                    Text("All Sources").tag(String?.none)
                    ForEach(store.sources) { Text($0.name).tag(Optional($0.id)) }
                } label: {
                    Label(sourceTitle, systemImage: "antenna.radiowaves.left.and.right")
                }
                .pickerStyle(.menu)
                .fixedSize()
                .focused(focus, equals: .source)
            }
            TextField("Search Channels", text: Binding(get: { store.searchText }, set: { store.setSearchText($0) }))
                .frame(maxWidth: 440)
                .focused(focus, equals: .search)
            Spacer(minLength: 0)
            if let total = store.total {
                Text("\(total) channels").foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
            Menu {
                Toggle(isOn: $store.showHidden) {
                    Label("Show Hidden Channels", systemImage: "eye.slash")
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh Channels", systemImage: "arrow.clockwise")
                }
                if !picking {
                    if let saved = resume.saved {
                        Button {
                            MultiscreenPresenter.open(.resume(saved))
                        } label: {
                            Label("Resume Multiscreen", systemImage: "arrow.counterclockwise")
                        }
                    }
                    Button {
                        MultiscreenPresenter.open(.pick)
                    } label: {
                        Label("Multiscreen", systemImage: "rectangle.split.2x2")
                    }
                    Button(action: openRecordings) {
                        Label("Recordings", systemImage: "record.circle")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis").labelStyle(.iconOnly)
            }
            .focused(focus, equals: .more)
            .accessibilityLabel("More Options")
        }
        .font(.callout)
        .focusSection()
    }

    private var sourceTitle: String {
        store.sources.first { $0.id == store.sourceID }?.name ?? String(localized: "All Sources")
    }
}

/// The Live tab as multiscreen's channel picker: its title, the screen's current channel (marked
/// in the list), and what a pick and Menu do.
struct LivePicker {
    let title: String
    let playingChannelID: String?
    let error: String?
    let onPick: LiveChannelPick
    let onClose: () -> Void
}

/// What a pick does in the picker; a class, so the environment compares it by identity.
final class LiveChannelPick {
    let run: (LiveChannel) -> Void

    init(_ run: @escaping (LiveChannel) -> Void) {
        self.run = run
    }
}

extension EnvironmentValues {
    /// Replaces playing a channel when the Live views pick one for multiscreen.
    @Entry var liveChannelPick: LiveChannelPick?
    /// The channel the picker's screen shows, marked in the list.
    @Entry var livePlayingChannelID: String?
}

/// Long-press actions shared by channel cards and guide cells.
struct LiveChannelMenu: View {
    let channel: LiveChannel
    @EnvironmentObject private var store: LiveStore

    var body: some View {
        Button {
            store.toggleFavorite(channel)
        } label: {
            if store.favorites.contains(channel.id) {
                Label("Remove from Favorites", systemImage: "star.slash")
            } else {
                Label("Add to Favorites", systemImage: "star")
            }
        }
        Button {
            store.toggleHidden(channel)
        } label: {
            if store.hidden.contains(channel.id) {
                Label("Show Channel", systemImage: "eye")
            } else {
                Label("Hide Channel", systemImage: "eye.slash")
            }
        }
    }
}

/// A channel's logo fitted in a box, or its name when there is no logo.
struct ChannelLogo: View {
    let channel: LiveChannel
    let size: CGSize
    var font: Font = .headline
    /// Without a logo: the channel's name, or (where the name is shown beside it) a TV symbol.
    var namesChannel = true

    var body: some View {
        RemoteImage(url: channel.logoURL, size: size, contentMode: .fit) { failed in
            if failed, !namesChannel {
                Image(systemName: "tv").font(font).foregroundStyle(.tertiary)
            } else if failed {
                Text(channel.name)
                    .font(font)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .frame(width: size.width, height: size.height)
            }
        }
    }
}
