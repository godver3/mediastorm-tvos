import SwiftUI

struct MainTabs: View {
    /// One per profile (the tabs are rebuilt on a profile switch), shared by every tab.
    @StateObject private var watchlist = WatchlistStore()
    @StateObject private var customLists = CustomListsStore()
    @StateObject private var titles = TitleStateStore()
    @StateObject private var listShelves = ListShelvesStore()
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @ObservedObject var homeViews = HomeViewsStore.shared
    @State var homePath = NavigationPath()
    /// The details pages pushed over each Home view's own tab, by view.
    @State var viewPaths: [String: NavigationPath] = [:]
    @State var tab: MainTab
    @State var surpriseError: String?
    @State var findingSurprise = false
    @State var askingAI = false
    @State private var aiPrompt = ""
    @ObservedObject private var links = DeepLinkRouter.shared
    @ObservedObject var menu = MenuTabsStore.shared
    @ObservedObject private var menuStyle = MenuStyleStore.shared

    enum MainTab: Hashable { case home, homeView(String), live, recordings, sports, watchlist, lists, calendar, search, settings }

    init() {
        let views = HomeViewsStore.shared
        views.configure(profileID: APIClient.shared.profileID)
        _tab = State(initialValue: .home)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab(homeTabTitle, systemImage: "house", value: .home) {
                homeStack(view: homeTabView, path: $homePath, viewChoices: homeViewChoices)
            }
            // Movies, Shows and pages with tabs, then the menu's sections, in this device's
            // order (Settings › Menu › Tab Order).
            ForEach(orderedTabs, id: \.self) { item in
                Tab(tabTitle(item), systemImage: tabSymbol(item), value: item, role: item == .search ? .search : nil) {
                    tabContent(item)
                }
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                NavigationStack { SettingsView() }.pinsSideMenu()
            }
        }
        .modifier(MenuStyleModifier(style: menuStyle.style))
        .modifier(HomeViewTabs(tabs: self))
        .environmentObject(watchlist)
        .environmentObject(customLists)
        .environmentObject(titles)
        .environmentObject(listShelves)
        .task { await watchlist.refresh() }
        .task { await customLists.refresh() }
        .task { await titles.refresh() }
        .task { await listShelves.refresh() }
        .task { await BadgeSettingsStore.shared.refresh() }
        // Hidden / Set Aside / watched state behind the long-press menus.
        .onReceive(NotificationCenter.default.publisher(for: .continueWatchingChanged)) { _ in
            Task { await titles.refreshContinueWatching() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .titleStateChanged)) { _ in
            customLists.titlesChanged()
            Task { await watchlist.refresh() }
        }
        .onChange(of: playback.sessionsEnded) { Task { await titles.refresh() } }
        .overlay { TitleToast().environmentObject(titles) }
        .modifier(LongPressModals(customLists: customLists, titles: titles))
        .task { await menu.refresh(profileID: APIClient.shared.profileID) }
        .onAppear(perform: openPendingLink)
        .onAppear { UnfocusedMenuGuard.shared.tabsAppeared() }
        .onChange(of: links.pending) { openPendingLink() }
        .alert("Couldn't Pick a Title", isPresented: Binding(get: { surpriseError != nil }, set: { if !$0 { surpriseError = nil } }),
               presenting: surpriseError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
        .alert("Ask AI", isPresented: $askingAI) {
            TextField("A cozy mystery from the 90s", text: $aiPrompt)
            Button("Ask") { submitAIPrompt() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Describe what you're in the mood for.")
        }
    }

    /// A tab's screen: a Home view's rows, or a menu section in its navigation stack.
    @ViewBuilder
    private func tabContent(_ item: MainTab) -> some View {
        switch item {
        case let .homeView(view):
            homeStack(view: view, path: viewPath(view))
        case .live:
            NavigationStack { LiveView() }.pinsSideMenu()
        case .recordings:
            NavigationStack { RecordingsView() }.pinsSideMenu()
        case .sports:
            NavigationStack { SportsHubView() }.pinsSideMenu()
        case .watchlist:
            NavigationStack {
                WatchlistView()
                    .navigationDestination(for: DetailsTarget.self, destination: details)
                    .navigationDestination(for: PersonRef.self) { PersonPage(person: $0).pinsSideMenu() }
            }
            .pinsSideMenu()
        case .lists:
            NavigationStack {
                ListsView()
                    .navigationDestination(for: BrowseList.self) { ListPage(list: $0).pinsSideMenu() }
                    .navigationDestination(for: LibraryShowTarget.self) { LibraryShowView(target: $0).pinsSideMenu() }
                    .navigationDestination(for: DetailsTarget.self, destination: details)
                    .navigationDestination(for: PersonRef.self) { PersonPage(person: $0).pinsSideMenu() }
            }
            .pinsSideMenu()
        case .calendar:
            NavigationStack {
                CalendarView()
                    .navigationDestination(for: DetailsTarget.self, destination: details)
                    .navigationDestination(for: PersonRef.self) { PersonPage(person: $0).pinsSideMenu() }
            }
            .pinsSideMenu()
        case .search:
            NavigationStack {
                SearchView()
                    .navigationDestination(for: DetailsTarget.self, destination: details)
                    .navigationDestination(for: PersonRef.self) { PersonPage(person: $0).pinsSideMenu() }
            }
            .pinsSideMenu()
        case .home, .settings:
            EmptyView()
        }
    }

    /// A Home view in its tab: its rows (one store per view, kept across switches) and the
    /// pages pushed over them. A new view starts at the top with no focus memory.
    private func homeStack(view: String, path: Binding<NavigationPath>, viewChoices: [String]? = nil) -> some View {
        NavigationStack(path: path) {
            HomeView(store: homeViews.store(for: view), isCovered: !path.wrappedValue.isEmpty, viewChoices: viewChoices)
                .id(view)
                .pinsSideMenu()
                .navigationDestination(for: DetailsTarget.self, destination: details)
                .navigationDestination(for: PersonRef.self) { PersonPage(person: $0).pinsSideMenu() }
                .navigationDestination(for: BrowseList.self) { ListPage(list: $0).pinsSideMenu() }
                .navigationDestination(for: LibraryShowTarget.self) { LibraryShowView(target: $0).pinsSideMenu() }
        }
        .pinsSideMenu()
        .environment(\.homeAction) { homeAction($0, view: view, path: path) }
        .environment(\.openHomeDetails) { path.wrappedValue.append($0) }
    }

    /// Watch Something: Search switches to the Search tab; Surprise Me asks the server
    /// for a pick (of the view's media type) and opens it over Home; Ask AI asks for a
    /// description, then opens the server's picks for it as a list over Home.
    private func homeAction(_ action: HomeAction, view: String, path: Binding<NavigationPath>) {
        switch action {
        case .search:
            tab = .search
        case .askAI:
            aiPrompt = ""
            askingAI = true
        case .surprise:
            guard !findingSurprise else { return }
            findingSurprise = true
            let filter = homeViews.filter(view)
            Task {
                defer { findingSurprise = false }
                do {
                    path.wrappedValue.append(DetailsTarget(try await APIClient.shared.surprise(filter: filter)))
                } catch {
                    surpriseError = error.localizedDescription
                }
            }
        }
    }

    private func submitAIPrompt() {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        switch tab {
        case let .homeView(view): viewPaths[view, default: NavigationPath()].append(BrowseList.askAI(prompt))
        default: homePath.append(BrowseList.askAI(prompt))
        }
    }

    /// A Top Shelf link: its details page over Home, replacing whatever was open there
    /// (as the Expo app replaces rather than pushes for a Top Shelf details route).
    private func openPendingLink() {
        guard let link = links.take() else { return }
        tab = .home
        homePath = NavigationPath([link.target])
    }

    /// A details page (it starts its stream resolving as it appears).
    private func details(_ target: DetailsTarget) -> some View {
        DetailsView(target: target).pinsSideMenu()
    }
}
