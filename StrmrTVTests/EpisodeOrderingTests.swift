import XCTest
@testable import StrmrTV

/// Alternate episode orderings: the server's ordering list and per-episode numbering decode,
/// and an episode's ordering keeps prequeues and source searches for "S01E02" in different
/// orderings apart.
@MainActor
final class EpisodeOrderingTests: XCTestCase {
    private let series = DetailsTarget(titleID: "tvdb:series:74852", name: "Avatar", isMovie: false, year: 2005,
                                       tmdbID: nil, imdbID: nil, tvdbID: "74852", posterURL: nil,
                                       textPosterURL: nil, backdropURL: nil, logoURL: nil, overview: nil)

    func testSeriesDetailsDecodesOrderingsAndEpisodeNumbering() throws {
        let json = """
        {"title":{"id":"tvdb:series:74852","name":"Avatar","mediaType":"series"},
         "availableOrderings":[{"type":"official","name":"Aired Order","seasonCount":3,"isOfficial":true},
                               {"type":"dvd","name":"DVD Order","seasonCount":3,"isOfficial":false}],
         "activeOrdering":"dvd",
         "seasons":[{"id":"s1","name":"Book One","number":1,"episodes":[
            {"id":"e1","name":"The Boy in the Iceberg","seasonNumber":1,"episodeNumber":1,
             "numbering":{"seriesId":"tvdb:series:74852","ordering":"dvd"}}]}]}
        """
        let details = try JSONDecoder().decode(SeriesDetails.self, from: Data(json.utf8))
        XCTAssertEqual(details.availableOrderings?.map(\.type), ["official", "dvd"])
        XCTAssertEqual(details.availableOrderings?.first?.isOfficial, true)
        XCTAssertEqual(details.activeOrdering, "dvd")
        XCTAssertEqual(details.seasons.first?.episodes.first?.numbering,
                       EpisodeNumbering(seriesId: "tvdb:series:74852", ordering: "dvd"))
    }

    func testSeriesDetailsWithoutOrderingsStillDecodes() throws {
        let json = """
        {"title":{"id":"tmdb:tv:1","name":"Show","mediaType":"series"},
         "seasons":[{"id":"s1","name":"S1","number":1,"episodes":[
            {"id":"e1","name":"Pilot","seasonNumber":1,"episodeNumber":1}]}]}
        """
        let details = try JSONDecoder().decode(SeriesDetails.self, from: Data(json.utf8))
        XCTAssertNil(details.availableOrderings)
        XCTAssertNil(details.seasons.first?.episodes.first?.numbering)
    }

    func testNumberingJSONMatchesServerShape() {
        let dvd = EpisodeNumbering(seriesId: "tvdb:series:74852", ordering: "dvd").json
        XCTAssertEqual(dvd["seriesId"] as? String, "tvdb:series:74852")
        XCTAssertEqual(dvd["ordering"] as? String, "dvd")
        XCTAssertNil(EpisodeNumbering(seriesId: "x", ordering: "").json["ordering"])
    }

    func testPrequeueKeySeparatesOrderings() {
        func request(_ ordering: String?) -> PlaybackRequest {
            let numbering = ordering.map { EpisodeNumbering(seriesId: "tvdb:series:74852", ordering: $0) }
            return PlaybackRequest(title: series,
                                   episode: .init(season: 1, episode: 2, absolute: nil, name: nil, itemID: nil,
                                                  numbering: numbering),
                                   start: nil)
        }
        XCTAssertNotEqual(request("official").prequeueKey, request("dvd").prequeueKey)
        XCTAssertEqual(request("dvd").prequeueKey, request("dvd").prequeueKey)
    }

    func testSourceSearchKeySeparatesOrderings() {
        let official = SourceSearch.Key(titleID: series.titleID, query: "Avatar S01E02", ordering: "official")
        let dvd = SourceSearch.Key(titleID: series.titleID, query: "Avatar S01E02", ordering: "dvd")
        XCTAssertNotEqual(official, dvd)
    }
}
