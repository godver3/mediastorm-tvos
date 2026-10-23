import SwiftUI

/// The Search tab, a port of the Expo TV search (`TVSearchScreen`) under the native tvOS
/// keyboard. Before typing, Top 10 Today across the whole width; once a query is typed, a
/// rail on the left (the query and the result names) beside the movies, series and people
/// merged by relevance. Kids profiles get no rail; curated kids profiles can't search.
struct SearchView: View {
    @StateObject private var store = SearchStore()
    @State private var gridWidth: CGFloat = 0

    private var profile: Profile? { AppSession.shared.profile }
    /// The suggestions rail, only while a query is typed; never on kids profiles (Expo's
    /// `canProfileAccessSearchGroupings`).
    private var showsRail: Bool { store.hasQuery && profile?.isKidsProfile != true }
    @Environment(\.sidebarInset) private var sidebarInset

    var body: some View {
        if profile?.isKidsCurated == true {
            CuratedSearchNotice()
        } else {
            content
                .searchable(text: $store.query, prompt: "Movies, shows and people")
                // The search field starts at the top left, under the side menu's pill.
                .padding(.top, sidebarInset)
                .task { store.loadTopTen() }
        }
    }

    private var content: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 48) {
                if showsRail {
                    rail
                        .frame(width: 340)
                        .focusSection()
                }
                results
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
                    .focusSection()
            }
            // Room inside the scroll view for the focus lift, so it can clip at its edges
            // without cutting a focused poster or drawing over the keyboard.
            .padding(.vertical, 50)
            .padding(.horizontal, CardGridLayout.inset)
        }
    }

    // MARK: Rail

    @ViewBuilder
    private var rail: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.suggestions, id: \.self) { suggestion in
                SearchRailButton(label: suggestion) { store.query = suggestion }
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let notice = store.hasQuery && store.resultQuery == store.normalizedQuery && !store.loading ? store.notice : nil {
                HStack(spacing: 30) {
                    Text(notice).foregroundStyle(.secondary)
                    Button("Retry") { store.retry() }
                }
            }
            if !store.hasQuery {
                Text("Top 10 Today").font(.headline)
            }
            if store.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 100)
            } else if !store.titles.isEmpty {
                grid
            } else if store.notice == nil || !store.hasQuery {
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass").font(.system(size: 44)).foregroundStyle(.tertiary)
                    Text("Enter another term to see matching titles").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            }
        }
    }

    /// Expo's grid: 4 columns beside the rail, 6 without it; narrower when they don't fit
    /// at the shared poster width (a tvOS 27 keyboard on the left takes room).
    private var layout: (columns: [GridItem], width: CGFloat) {
        let spacing = CardGridLayout.spacing
        let available = max(gridWidth, PosterCard.width)
        let fit = Int((available + spacing) / (PosterCard.width * 0.8 + spacing))
        let count = max(1, min(showsRail ? 4 : 6, fit))
        let width = min(PosterCard.width, ((available - spacing * CGFloat(count - 1)) / CGFloat(count)).rounded(.down))
        return (Array(repeating: GridItem(.fixed(width), spacing: spacing, alignment: .top), count: count), width)
    }

    private var grid: some View {
        let layout = layout
        return LazyVGrid(columns: layout.columns, alignment: .leading, spacing: 70) {
            let ranked = !store.hasQuery
            ForEach(Array(uniqueTitles.enumerated()), id: \.element.id) { index, title in
                if let person = PersonCard(title: title, width: layout.width) {
                    person
                } else {
                    // Top 10 Today before typing: ranked "#1"–"#10", as on Home.
                    PosterCard(title: title, width: layout.width, rank: ranked ? index + 1 : nil)
                }
            }
        }
    }

    /// A list can name a title twice; the grid needs unique IDs.
    private var uniqueTitles: [Title] {
        var seen = Set<String>()
        return store.titles.filter { seen.insert($0.id).inserted }
    }
}

/// Expo's notice for kids profiles limited to curated lists, which can't search.
private struct CuratedSearchNotice: View {
    var body: some View {
        HStack(spacing: 30) {
            Image(systemName: "checkmark.shield").font(.system(size: 44)).foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 8) {
                Text("Search is unavailable for this profile").font(.headline)
                Text("Content is limited to the curated lists selected for this profile.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Something focusable, so the tab bar can move off this page and back.
        .focusable()
    }
}
