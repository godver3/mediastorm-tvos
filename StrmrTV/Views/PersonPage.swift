import SwiftUI

/// A cast member's page, opened from the details page's Cast row: their photo and
/// biography over a grid of the titles they appear in (the Expo shelf's person mode).
struct PersonPage: View {
    let person: PersonRef

    @State private var details: PersonDetails?
    @State private var loadError: String?
    @State private var gridWidth: CGFloat = 0
    /// The biography shown whole over the page, blurred behind it.
    @State private var showsFullBio = false
    @FocusState private var bioFocused: Bool

    var body: some View {
        GridPage(title: person.name, gridWidth: $gridWidth) {
            if let details {
                header(details.person)
                let titles = details.filmography ?? []
                if titles.isEmpty {
                    GridMessage(text: String(localized: "No titles found."))
                } else {
                    CardGrid(items: titles, cardWidth: PosterCard.width, available: gridWidth) { title, width in
                        PosterCard(title: title, width: width)
                    }
                }
            } else if let loadError {
                GridMessage(text: loadError)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 100)
            }
        }
        .defaultFocus($bioFocused, true)
        .disabled(showsFullBio)
        .blur(radius: showsFullBio ? 40 : 0)
        .overlay {
            if showsFullBio, let bio = biography(details?.person) {
                FullTextOverlay(title: details?.person.name ?? person.name, text: bio) {
                    showsFullBio = false
                    bioFocused = true
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsFullBio)
        .task { await load() }
    }

    private func biography(_ info: PersonDetails.Person?) -> String? {
        let bio = info?.biography?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bio.isEmpty ? nil : bio
    }

    @ViewBuilder
    private func header(_ info: PersonDetails.Person) -> some View {
        let bio = biography(info)
        if info.profileUrl ?? person.profileURL != nil || bio != nil {
            HStack(alignment: .top, spacing: 40) {
                CastPhoto(url: info.profileUrl ?? person.profileURL, size: CGSize(width: 200, height: 300))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 20) {
                    if let knownFor = info.knownFor, !knownFor.isEmpty {
                        Text(knownFor).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if let bio {
                        ExpandableText(text: bio) { showsFullBio = true }
                            .focused($bioFocused)
                            // The page opens on the bio; `defaultFocus` alone misses it, as
                            // it arrives after the page is already focused.
                            .onAppear { Task { bioFocused = true } }
                    }
                }
                .frame(maxWidth: 1100, alignment: .leading)
            }
        }
    }

    private func load() async {
        do {
            let loaded = try await APIClient.shared.person(id: person.id)
            // A person can be credited twice on one title; the grid needs unique IDs.
            var seen = Set<String>()
            details = PersonDetails(person: loaded.person,
                                    filmography: loaded.filmography?.filter { seen.insert($0.id).inserted })
            loadError = nil
        } catch {
            if details == nil { loadError = error.localizedDescription }
        }
    }
}

/// A cast member's portrait, or a person symbol when there is none.
struct CastPhoto: View {
    let url: String?
    let size: CGSize

    var body: some View {
        RemoteImage(url: Artwork.url(url, size: "w342"), size: size) { _ in
            Rectangle().fill(.quaternary)
                .overlay(Image(systemName: "person.fill").font(.system(size: size.width * 0.35)).foregroundStyle(.secondary))
        }
    }
}
