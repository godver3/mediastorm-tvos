#if os(iOS)
import SwiftUI

/// Home on a phone: the chosen Home view's shelves from the shared `HomeStore`, each a
/// horizontally scrolling row, poster or 16:9 as the row's `ShelfStyle` says. The toolbar's
/// menu switches Home views (Home, Movies, Shows and the profile's pages), as the Expo
/// app's view picker. Watch Something cards search, pick a surprise or ask the AI.
struct MobileHomeView: View {
    @ObservedObject private var views = HomeViewsStore.shared

    var body: some View {
        MobileHomeContent(store: views.store(for: views.selected))
            .id(views.selected)
            .navigationTitle(views.label(views.selected))
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { viewMenu }
            }
            .task { await views.refresh() }
    }

    private var viewMenu: some View {
        Menu {
            Picker("Home View", selection: Binding(get: { views.selected }, set: { views.select($0) })) {
                ForEach(views.ids, id: \.self) { view in
                    Label(views.label(view), systemImage: views.icon(view)).tag(view)
                }
            }
        } label: {
            Label("Home View", systemImage: views.icon(views.selected))
        }
        .accessibilityIdentifier("homeViewSwitcher")
    }
}

/// One Home view's page.
private struct MobileHomeContent: View {
    @ObservedObject var store: HomeStore
    @EnvironmentObject private var watchlist: WatchlistStore
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @ObservedObject private var layout = HomeLayoutStore.shared
    @ObservedObject private var views = HomeViewsStore.shared
    @ObservedObject private var style = HomeStyleStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var searching = false
    @State private var surprisePick: DetailsTarget?
    @State private var findingSurprise = false
    @State private var surpriseError: String?
    @State private var askingAI = false
    @State private var aiPrompt = ""
    @State private var aiList: BrowseList?

    var body: some View {
        lifecycle(page)
            .environment(\.homeAction) { run($0) }
            .navigationDestination(isPresented: $searching) { MobileSearchView() }
            .navigationDestination(item: $surprisePick) { MobileDetailsView(target: $0) }
            .navigationDestination(item: $aiList) { MobileListPage(list: $0) }
            .modifier(actionAlerts)
    }

    private var page: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                let carousel = carouselSource
                if let shelf = carousel.shelf { MobileHomeCarousel(shelf: shelf) }
                ForEach(store.slots) { slot in
                    switch slot {
                    case _ where slot.id == carousel.id:
                        EmptyView()
                    case let .shelf(shelf) where !shelf.cards.isEmpty:
                        MobileShelfRow(shelf: shelf, landscape: layout.style(for: shelf.id) == .landscape,
                                       onHide: hideAction(shelf))
                    case let .loading(_, title):
                        MobileShelfPlaceholder(title: title)
                    default:
                        EmptyView()
                    }
                }
                if store.slots.isEmpty, !store.isLoading {
                    status.padding(.top, 60)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .overlay { if store.slots.isEmpty, store.isLoading { ProgressView() } }
        .refreshable { await store.load() }
    }

    private func lifecycle(_ content: some View) -> some View {
        content
            .task {
                store.watchlist = watchlist.items
                if store.hasLoaded {
                    store.activate()
                    await store.refreshIfStale()
                } else {
                    await store.load()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refreshIfStale() } }
            }
            .onChange(of: watchlist.items) { _, items in store.watchlist = items }
            .onChange(of: playback.sessionsEnded) { Task { await store.reloadPlaybackRows() } }
            .onReceive(NotificationCenter.default.publisher(for: .continueWatchingChanged)) { _ in
                Task { await store.reloadPlaybackRows() }
            }
            // Hidden / unhidden titles leave or rejoin every row the server builds.
            .onReceive(NotificationCenter.default.publisher(for: .titleStateChanged)) { _ in
                Task { await store.load() }
            }
    }

    private var actionAlerts: ActionAlerts {
        ActionAlerts(surpriseError: $surpriseError, askingAI: $askingAI, aiPrompt: $aiPrompt, aiList: $aiList)
    }
}

/// Surprise Me's failure and Ask AI's prompt.
private struct ActionAlerts: ViewModifier {
    @Binding var surpriseError: String?
    @Binding var askingAI: Bool
    @Binding var aiPrompt: String
    @Binding var aiList: BrowseList?

    func body(content: Content) -> some View {
        content
            .alert("Couldn't Pick a Title", isPresented: Binding(get: { surpriseError != nil }, set: { if !$0 { surpriseError = nil } }),
                   presenting: surpriseError) { _ in
                Button("OK", role: .cancel) {}
            } message: { Text($0) }
            .alert("Ask AI", isPresented: $askingAI) {
                TextField("A cozy mystery from the 90s", text: $aiPrompt)
                Button("Ask") {
                    let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !prompt.isEmpty { aiList = .askAI(prompt) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Describe what you're in the mood for.")
            }
    }
}

private extension MobileHomeContent {
    @ViewBuilder
    private var status: some View {
        if let error = store.loadError {
            ContentUnavailableView {
                Label("Couldn't Load Home", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await store.load() } }.buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView("Nothing on Home", systemImage: "house",
                                   description: Text("Turn on shelves for this profile in the server's settings."))
        }
    }

    /// The Top Carousel's row (Settings › Home), left out of the rows below; empty with it off.
    var carouselSource: HomeCarouselSource {
        style.topCarousel ? .resolve(slots: store.slots, chosen: style.carouselRow) : HomeCarouselSource()
    }

    func hideAction(_ shelf: HomeShelf) -> ((HomeCard) -> Void)? {
        guard shelf.id == HomeShelf.continueWatchingID else { return nil }
        return { hide($0) }
    }

    /// Hide from Continue Watching: the card leaves at once; a failure brings it back.
    private func hide(_ card: HomeCard) {
        withAnimation { store.remove(card: card.id, from: HomeShelf.continueWatchingID) }
        Task {
            do { try await APIClient.shared.hideFromContinueWatching(seriesID: card.id) } catch { await store.reloadPlaybackRows() }
        }
    }

    /// Watch Something: Search opens search over Home; Surprise Me asks the server for a pick
    /// of the view's media type and opens it; Ask AI asks for a description, then opens the
    /// server's picks for it as a list.
    private func run(_ action: HomeAction) {
        switch action {
        case .search:
            searching = true
        case .askAI:
            aiPrompt = ""
            askingAI = true
        case .surprise:
            guard !findingSurprise else { return }
            findingSurprise = true
            let filter = views.filter(store.view)
            Task {
                defer { findingSurprise = false }
                do {
                    surprisePick = DetailsTarget(try await APIClient.shared.surprise(filter: filter))
                } catch {
                    surpriseError = error.localizedDescription
                }
            }
        }
    }
}
#endif
