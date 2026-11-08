#if os(iOS)
import SwiftUI

/// A cast member's page, opened from a details page's Cast row: their portrait, what they are
/// known for and their biography (tap to read it all), over a poster grid of the titles they
/// appear in, sorted Popular (the server's order) or Chronological, as the Expo person shelf.
/// Hidden titles are left out.
struct MobilePersonView: View {
    let person: PersonRef

    @EnvironmentObject private var titles: TitleStateStore
    @State private var details: PersonDetails?
    @State private var loadError: String?
    @State private var showsBio = false
    @AppStorage("strmr.mobile.filmographySort") private var sort = Sort.popular

    enum Sort: String, CaseIterable, Identifiable {
        case popular, chronological
        var id: String { rawValue }
        var label: LocalizedStringKey { self == .popular ? "Popular" : "Chronological" }
        var symbol: String { self == .popular ? "flame" : "calendar" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let details {
                    header(details.person)
                    let shown = filmography(details)
                    if shown.isEmpty {
                        ContentUnavailableView("No Titles Found", systemImage: "film.stack")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 12, alignment: .top)],
                                  alignment: .leading, spacing: 18) {
                            ForEach(shown) { title in
                                MobileGridPoster(title: title)
                            }
                        }
                    }
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't Load", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(16)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Color.brandBackground.ignoresSafeArea())
        .navigationTitle(details?.person.name ?? person.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .sheet(isPresented: $showsBio) { bioSheet }
        .task { await load() }
    }

    private func biography(_ info: PersonDetails.Person?) -> String? {
        let bio = info?.biography?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bio.isEmpty ? nil : bio
    }

    private func header(_ info: PersonDetails.Person) -> some View {
        HStack(alignment: .top, spacing: 16) {
            CastPhoto(url: info.profileUrl ?? person.profileURL, size: CGSize(width: 110, height: 165))
                .frame(width: 110, height: 165)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                if let knownFor = info.knownFor, !knownFor.isEmpty {
                    Text(knownFor).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                if let bio = biography(info) {
                    Button { showsBio = true } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bio).font(.subheadline).foregroundStyle(.primary).lineLimit(6)
                                .multilineTextAlignment(.leading)
                            Text("More").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the full biography")
                }
            }
        }
    }

    private var bioSheet: some View {
        NavigationStack {
            ScrollView {
                Text(biography(details?.person) ?? "")
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle(details?.person.name ?? person.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showsBio = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Popular keeps the server's order; Chronological sorts by year, undated titles last.
    private func filmography(_ details: PersonDetails) -> [Title] {
        let visible = (details.filmography ?? []).filter { !titles.isHidden(DetailsTarget($0)) }
        guard sort == .chronological else { return visible }
        return visible.enumerated().sorted { a, b in
            switch (a.element.year, b.element.year) {
            case let (x?, y?) where x != y: x < y
            case (nil, _?): false
            case (_?, nil): true
            default: a.offset < b.offset
            }
        }.map(\.element)
    }

    private func load() async {
        do {
            let loaded = try await APIClient.shared.person(id: person.id)
            var seen = Set<String>()
            details = PersonDetails(person: loaded.person,
                                    filmography: loaded.filmography?.filter { seen.insert($0.id).inserted })
            loadError = nil
        } catch {
            if details == nil, !error.isCancellation { loadError = error.localizedDescription }
        }
    }
}

/// A grid poster that fills its column, opening the title's page.
struct MobileGridPoster: View {
    let title: Title

    var body: some View {
        NavigationLink(value: DetailsTarget(title)) {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            RemoteImage(url: Artwork.url(title.poster?.url, size: "w342"), size: geo.size) { _ in
                                ZStack {
                                    Color.white.opacity(0.08)
                                    Text(title.name).font(.caption).multilineTextAlignment(.center).padding(6)
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title.name).font(.caption.weight(.semibold)).lineLimit(1)
                if let year = title.year {
                    Text(String(year)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
#endif
