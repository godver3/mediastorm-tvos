#if os(iOS)
import SwiftUI

/// Search on a phone, a port of the Expo mobile search on the shared `SearchStore`: Top 10
/// Today before anything is typed, then the movie, series and person searches merged by
/// relevance as they come in. Scopes narrow to movies or shows (people only show under
/// All, as in Expo); the empty field suggests recent searches. Curated kids profiles can't
/// search.
struct MobileSearchView: View {
    @StateObject private var store = SearchStore()
    @State private var scope: Scope = .all
    @State private var recents = MobileRecentSearches()
    @FocusState private var fieldFocused: Bool

    enum Scope: String, CaseIterable, Identifiable {
        case all, movies, shows
        var id: Self { self }

        var label: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .movies: "Movies"
            case .shows: "TV Shows"
            }
        }

        func includes(_ title: Title) -> Bool {
            switch self {
            case .all: true
            case .movies: title.mediaType == "movie"
            case .shows: title.mediaType == "series" || title.mediaType == "tv"
            }
        }
    }

    private var profile: Profile? { AppSession.shared.profile }

    var body: some View {
        Group {
            if profile?.isKidsCurated == true {
                ContentUnavailableView("Search Is Unavailable", systemImage: "checkmark.shield",
                                       description: Text("Content is limited to the curated lists selected for this profile."))
            } else {
                content
                    .searchable(text: $store.query, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: "Movies, shows and people")
                    .searchFocused($fieldFocused)
                    .searchScopes($scope, activation: .onSearchPresentation) {
                        ForEach(Scope.allCases) { Text($0.label).tag($0) }
                    }
                    .searchSuggestions { suggestions }
                    .onSubmit(of: .search) { recents.add(store.normalizedQuery) }
                    .task { store.loadTopTen() }
                    .onReceive(NotificationCenter.default.publisher(for: .mobileSearchTabReselected)) { _ in
                        focusField()
                    }
            }
        }
        .navigationTitle("Search")
    }

    /// Pressing the Search tab again focuses the field. A press from a page pushed over
    /// Search pops back here first, and focus set mid-pop is dropped, so it tries again
    /// once the pop has finished.
    private func focusField() {
        fieldFocused = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if !fieldFocused { fieldFocused = true }
        }
    }

    // MARK: Suggestions

    @ViewBuilder
    private var suggestions: some View {
        if !store.hasQuery, !recents.items.isEmpty {
            Section {
                ForEach(recents.items, id: \.self) { recent in
                    Label(recent, systemImage: "clock.arrow.circlepath").searchCompletion(recent)
                }
            } header: {
                HStack {
                    Text("Recent Searches")
                    Spacer()
                    Button("Clear") { recents.clear() }.font(.footnote)
                }
            }
        }
    }

    // MARK: Results

    private var shown: [Title] {
        var seen = Set<String>()
        return store.titles.filter { scope.includes($0) && seen.insert($0.id).inserted }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let notice = store.hasQuery && store.resultQuery == store.normalizedQuery && !store.loading ? store.notice : nil {
                    HStack {
                        Label(notice, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") { store.retry() }.buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                }
                if !store.hasQuery {
                    Text("Top 10 Today").font(.title3.weight(.semibold)).padding(.horizontal, 16)
                }
                if !store.isLoading, !shown.isEmpty { grid }
            }
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.immediately)
        .overlay { placeholder }
    }

    @ViewBuilder
    private var placeholder: some View {
        if store.isLoading {
            ProgressView()
        } else if shown.isEmpty {
            if store.hasQuery, store.normalizedQuery.count >= SearchRanking.minQueryLength,
               store.resultQuery == store.normalizedQuery, store.notice == nil {
                ContentUnavailableView.search(text: store.normalizedQuery)
            } else if !store.hasQuery {
                ContentUnavailableView("Search MediaStorm", systemImage: "magnifyingglass",
                                       description: Text("Find movies, shows and people."))
            }
        }
    }

    private var grid: some View {
        let ranked = !store.hasQuery
        return MobilePosterGrid(items: Array(shown.enumerated()).map { RankedTitle(rank: $0.offset + 1, title: $0.element) }) { entry in
            if entry.title.mediaType == "person", let tmdbID = entry.title.tmdbId {
                MobilePersonCell(person: PersonRef(id: tmdbID, name: entry.title.name, profileURL: entry.title.poster?.url))
            } else {
                MobileGridCard(card: HomeCard(entry.title, rank: ranked ? entry.rank : nil))
            }
        }
    }
}

private struct RankedTitle: Identifiable {
    let rank: Int
    let title: Title
    var id: String { title.id }
}

/// A person result: a round photo with the name under it, opening their page.
struct MobilePersonCell: View {
    let person: PersonRef

    var body: some View {
        NavigationLink(value: person) {
            VStack(spacing: 6) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            RemoteImage(url: Artwork.url(person.profileURL, size: "w185"), size: geo.size) { _ in
                                ZStack {
                                    Circle().fill(.quaternary)
                                    Image(systemName: "person.fill").font(.title).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .clipShape(Circle())
                    .padding(.top, 8)
                Text(person.name).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                Text("Person").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.name)
    }
}

/// The profile's recent searches on this device (Expo keeps eight per profile).
@MainActor
struct MobileRecentSearches {
    private static let limit = 8
    private var key: String { "mobile.recentSearches.\(APIClient.shared.profileID)" }
    private(set) var items: [String]

    init() {
        items = UserDefaults.standard.stringArray(forKey: "mobile.recentSearches.\(APIClient.shared.profileID)") ?? []
    }

    mutating func add(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        items = Array(([query] + items.filter { $0.caseInsensitiveCompare(query) != .orderedSame }).prefix(Self.limit))
        UserDefaults.standard.set(items, forKey: key)
    }

    mutating func clear() {
        items = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
#endif
