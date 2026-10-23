import XCTest
@testable import StrmrTV

/// Library copies (local, Plex, Jellyfin): decoding the server's shapes, the best-first order
/// Play uses, episode mapping, the catalog ids a library card opens, library shelves and the
/// progress a library file reports.
@MainActor
final class LibraryTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func item(_ id: String, width: Int, height: Int, codec: String, hdr: String? = nil, gb: Double,
                      source: String = "plex", season: Int? = nil, episode: Int? = nil) -> String {
        """
        {"id":"\(id)","fileName":"\(id).mkv","sourceType":"\(source)","sizeBytes":\(Int64(gb * 1_000_000_000)),
         "seasonNumber":\(season.map(String.init) ?? "null"),"episodeNumber":\(episode.map(String.init) ?? "null"),
         "probe":{"durationSeconds":6000,"videoCodec":"\(codec)","width":\(width),"height":\(height)
                  \(hdr.map { ",\"hdrFormat\":\"\($0)\"" } ?? "")}}
        """
    }

    func testVersionsSortBestFirstWithQualityLabels() throws {
        let page = try decode(LibraryGroupPage.self, """
        {"groups":[{"id":"757910","groupType":"title","libraryType":"movie","title":"Example","tmdbId":1081003,
                    "items":[\(item("hd", width: 1920, height: 800, codec: "h264", gb: 6)),
                             \(item("uhd", width: 3840, height: 1608, codec: "hevc", hdr: "HDR10", gb: 21))]}],
         "total":1,"alphabetBuckets":["E"]}
        """)
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.alphabetBuckets, ["E"])
        let versions = LibraryVersions(group: page.groups[0], libraryName: "Films")
        XCTAssertEqual(versions.movie.map(\.id), ["uhd", "hd"])
        // Wide 4K counts as 4K by its width, not "1608p".
        XCTAssertEqual(versions.movie[0].quality, "4K · HEVC · HDR10")
        XCTAssertEqual(versions.movie[1].quality, "1080p · H.264")
        XCTAssertEqual(versions.movie[0].origin, "Plex · Films")
        XCTAssertEqual(versions.movie[0].size?.hasSuffix("28 Mbps"), true)
        XCTAssertEqual(versions.best(season: nil, episode: nil)?.id, "uhd")
    }

    func testEpisodesMapBySeasonAndEpisode() throws {
        let group = try decode(LibraryGroup.self, """
        {"id":"series:tmdb:tv:1","groupType":"show","libraryType":"show","title":"Show","tmdbId":1,
         "seasons":[{"seasonNumber":1,"episodes":[
            {"episodeNumber":1,"items":[\(item("s1e1", width: 1920, height: 1080, codec: "h264", gb: 2, source: "local"))]},
            {"episodeNumber":2,"items":[\(item("s1e2", width: 1280, height: 720, codec: "h264", gb: 1, source: "local"))]}]}]}
        """)
        let versions = LibraryVersions(group: group, libraryName: "TV")
        XCTAssertEqual(versions.best(season: 1, episode: 2)?.id, "s1e2")
        XCTAssertNil(versions.best(season: 1, episode: 3))
        XCTAssertTrue(versions.movie.isEmpty)
        XCTAssertEqual(versions.best(season: 1, episode: 1)?.origin, "Local · TV")
    }

    func testMatchesMergeLibrariesAndDropRepeatedFiles() throws {
        let matches = try decode([LibraryMatch].self, """
        [{"libraryId":"plex","libraryName":"Films","group":{"id":"1","title":"Example","libraryType":"movie",
            "items":[\(item("a", width: 1920, height: 1080, codec: "h264", gb: 8))]}},
         {"libraryId":"jf","libraryName":"Movies","group":{"id":"2","title":"Example","libraryType":"movie",
            "items":[\(item("b", width: 3840, height: 2160, codec: "hevc", gb: 40, source: "jellyfin")),
                     \(item("a", width: 1920, height: 1080, codec: "h264", gb: 8))]}}]
        """)
        let versions = LibraryVersions(matches: matches)
        XCTAssertEqual(versions.movie.map(\.id), ["b", "a"])
        XCTAssertEqual(versions.movie[0].source, .jellyfin)
    }

    func testCatalogTitleIDsAndTargets() throws {
        func group(_ ids: String, show: Bool = false) throws -> LibraryGroup {
            try decode(LibraryGroup.self, #"{"id":"g","title":"T","libraryType":"\#(show ? "show" : "movie")"\#(ids)}"#)
        }
        XCTAssertEqual(try group(#","tmdbId":5"#).catalogTitleID, "tmdb:movie:5")
        XCTAssertEqual(try group(#","tmdbId":5"#, show: true).catalogTitleID, "tmdb:tv:5")
        XCTAssertEqual(try group(#","tvdbId":7"#, show: true).catalogTitleID, "tvdb:series:7")
        XCTAssertEqual(try group(#","imdbId":"tt1""#).catalogTitleID, "tt1")
        XCTAssertNil(try group("").catalogTitleID)

        let matched = try XCTUnwrap(DetailsTarget(library: try group(#","tmdbId":5,"imdbId":"tt1""#)))
        XCTAssertTrue(matched.fromLibrary)
        XCTAssertEqual(matched.tmdbID, "5")
        XCTAssertNil(DetailsTarget(library: try group("")))
        XCTAssertFalse(DetailsTarget(unmatched: try group("")).hasCatalogIDs)
    }

    func testLibraryShelfIDs() throws {
        func shelf(_ json: String) throws -> ShelfConfig { try decode(ShelfConfig.self, json) }
        XCTAssertEqual(try shelf(#"{"id":"s1","type":"library","libraryId":"abc"}"#).libraryID, "abc")
        XCTAssertEqual(try shelf(#"{"id":"local-library-xyz","type":"local-library"}"#).libraryID, "xyz")
        XCTAssertNil(try shelf(#"{"id":"trending-movies","type":"builtin"}"#).libraryID)
    }

    func testLibraryCardsOpenDetailsOrTheirOwnLink() throws {
        let library = LibraryRef(id: "lib", name: "Films", type: "movie", sourceType: "plex")
        let matched = try decode(LibraryGroup.self, #"{"id":"1","title":"M","libraryType":"movie","tmdbId":9}"#)
        let unmatched = try decode(LibraryGroup.self, #"{"id":"2","title":"Home Video","libraryType":"movie"}"#)
        guard case let .details(target) = HomeCard(library: LibraryEntry(library: library, group: matched)).link else {
            return XCTFail("a matched title opens its details page")
        }
        XCTAssertTrue(target.fromLibrary)
        guard case .library = HomeCard(library: LibraryEntry(library: library, group: unmatched)).link else {
            return XCTFail("an unmatched title has its own link")
        }
    }

    private func version(_ id: String) throws -> LibraryVersion {
        LibraryVersion(item: try decode(LibraryItem.self, #"{"id":"\#(id)"}"#), libraryName: "Films")
    }

    func testLibraryProgressNamesItsSourcePath() throws {
        let target = DetailsTarget(titleID: "tmdb:movie:9", name: "M", isMovie: true, year: 2020, tmdbID: "9",
                                   imdbID: nil, tvdbID: nil, posterURL: "/api/library/items/x/artwork/poster",
                                   textPosterURL: nil, backdropURL: nil, logoURL: nil, overview: nil)
        var request = PlaybackRequest(title: target, episode: nil, start: nil)
        XCTAssertNil(request.progressReport(position: 10, duration: 100, paused: false, ended: false,
                                            sourcePath: "debrid/x.mkv")["sourcePath"])
        request.libraryVersion = try version("i")
        let body = request.progressReport(position: 10, duration: 100, paused: false, ended: false,
                                          sourcePath: "plexmedia:i")
        XCTAssertEqual(body["sourcePath"] as? String, "plexmedia:i")
        XCTAssertEqual(body["itemId"] as? String, "tmdb:movie:9")
        // A server-relative library poster means nothing in a notification.
        XCTAssertNil(body["posterUrl"])
    }

    func testUnmatchedFileProgressIsKeyedByItsStreamPath() throws {
        let group = try decode(LibraryGroup.self, #"{"id":"264995","title":"Home Video","libraryType":"movie"}"#)
        var request = PlaybackRequest(title: DetailsTarget(unmatched: group), episode: nil, start: nil)
        request.libraryVersion = try version("i")
        let body = request.progressReport(position: 10, duration: 100, paused: false, ended: false,
                                          sourcePath: "plexmedia:i")
        XCTAssertEqual(body["itemId"] as? String, "plexmedia:i")
        XCTAssertEqual(body["movieName"] as? String, "Home Video")
        XCTAssertNil(body["externalIds"])
        XCTAssertNil(body["seriesId"])
        XCTAssertEqual(request.streamMetadata(path: "plexmedia:i")["itemId"], "plexmedia:i")
        XCTAssertNil(request.streamMetadata(path: "plexmedia:i")["titleId"])
    }

    func testNextEpisodePlaysItsOwnLibraryCopy() throws {
        let group = try decode(LibraryGroup.self, """
        {"id":"g","title":"Show","libraryType":"show","tmdbId":1,"seasons":[{"seasonNumber":1,"episodes":[
            {"episodeNumber":1,"items":[{"id":"e1"}]},{"episodeNumber":2,"items":[{"id":"e2"}]}]}]}
        """)
        let target = try XCTUnwrap(DetailsTarget(library: group))
        func episode(_ n: Int) -> PlaybackRequest.EpisodeInfo {
            .init(season: 1, episode: n, absolute: nil, name: nil, itemID: nil)
        }
        let request = PlaybackRequest(title: target, episode: episode(1), start: nil, following: [episode(2), episode(3)],
                                      library: LibraryVersions(group: group, libraryName: "TV"))
        XCTAssertEqual(request.preferredLibraryVersion?.id, "e1")
        XCTAssertEqual(request.nextEpisode?.preferredLibraryVersion?.id, "e2")
        XCTAssertNil(request.nextEpisode?.nextEpisode?.preferredLibraryVersion)
    }
}
