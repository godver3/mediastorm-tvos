import Foundation

/// The server's local, Plex and Jellyfin libraries. Every call names the profile: the server
/// checks it against each library's access list and a kids profile's rating caps.
extension APIClient {
    /// `GET /api/library/libraries`: the libraries this profile may browse.
    func libraries() async throws -> [LibraryInfo] {
        try await send("GET", "/api/library/libraries", query: ["profileId": profileID])
    }

    /// One page of a library's titles, sorted and filtered by the server. `cards` asks for the
    /// light card shape (no files, no per-episode metadata), as the Expo rows and grid do.
    func libraryGroups(_ libraryID: String, limit: Int, offset: Int = 0, sort: String? = nil,
                       ascending: Bool = false, letter: String? = nil, mediaType: String? = nil,
                       search: String? = nil, cards: Bool = true) async throws -> LibraryGroupPage {
        var q = ["limit": String(limit), "offset": String(offset), "userId": profileID]
        if let sort {
            q["sort"] = sort
            q["dir"] = ascending ? "asc" : "desc"
        }
        if let letter { q["alphabet"] = letter }
        if let mediaType, mediaType != "all" { q["mediaType"] = mediaType }
        if let search, !search.isEmpty { q["query"] = search }
        if cards { q["include"] = "cards" }
        return try await send("GET", "/api/library/libraries/\(Self.segment(libraryID))/groups", query: q)
    }

    /// A grid page of a library (`BrowseList.library`). Default and Date Added are newest
    /// first for every source (the server's own default is A–Z for Plex and Jellyfin).
    func libraryPage(_ library: LibraryRef, options: BrowseOptions, limit: Int, offset: Int) async throws -> BrowsePage {
        let sort: (key: String, ascending: Bool) = switch options.sort {
        case .name: ("name", options.ascending)
        case .year: ("year", options.ascending)
        case .added: ("created", options.ascending)
        default: ("created", false)
        }
        let page = try await libraryGroups(library.id, limit: limit, offset: offset, sort: sort.key,
                                           ascending: sort.ascending,
                                           letter: options.sort == .name ? options.letter : nil)
        return BrowsePage(entries: page.groups.map { .library(LibraryEntry(library: library, group: $0)) },
                          total: page.total, letters: page.alphabetBuckets ?? [])
    }

    /// A title's copies in the profile's libraries: by its catalog ids, else its title and year.
    func libraryMatches(for target: DetailsTarget) async throws -> [LibraryMatch] {
        var q = ["mediaType": target.isMovie ? "movie" : "series", "title": target.name, "profileId": profileID]
        if target.hasCatalogIDs { q["titleId"] = target.titleID }
        if let v = target.tmdbID { q["tmdbId"] = v }
        if let v = target.imdbID { q["imdbId"] = v }
        if let v = target.tvdbID { q["tvdbId"] = v }
        if let v = target.year { q["year"] = String(v) }
        return try await send("GET", "/api/library/matches", query: q)
    }

    /// One library file's stream path. The server first checks a local file can be played
    /// (422 when it can't). `profileName` attributes the stream on the admin dashboard.
    func libraryPlayback(itemID: String) async throws -> LibraryPlaybackInfo {
        var q = ["profileId": profileID]
        if let profileName, !profileName.isEmpty { q["profileName"] = profileName }
        return try await send("GET", "/api/library/items/\(Self.segment(itemID))/playback", query: q, timeout: 60)
    }

    /// A card's group with its files (rows and grids carry none). The API has no call for one
    /// group, so this searches the library for the title and keeps only an exact id match.
    func libraryGroup(_ entry: LibraryEntry) async throws -> LibraryGroup {
        if entry.group.hasFiles { return entry.group }
        let page = try await libraryGroups(entry.library.id, limit: 200, search: entry.group.title, cards: false)
        guard let group = page.groups.first(where: { $0.id == entry.group.id }) else {
            throw APIError.notReady(String(localized: "This title is no longer in the library."))
        }
        return group
    }

    /// The server's resume decision for one progress record; nil when there is none.
    func resumeState(mediaType: String, itemID: String) async -> ResumeState? {
        struct Progress: Decodable { let resume: ResumeState? }
        let path = "\(profilePath)/history/progress/\(Self.segment(mediaType))/\(Self.segment(itemID))"
        let progress: Progress? = try? await send("GET", path, promptOnLock: false)
        return progress?.resume
    }
}
