import XCTest
@testable import StrmrTV

/// The Expo TV search's merge, person matching, rail and failure notices
/// (`hooks/useApi.ts`, `components/search/person-results.ts`, `TVSearchScreen.tsx`).
final class SearchRankingTests: XCTestCase {
    private func result(_ id: String, _ name: String, _ type: String, score: Double?, year: Int? = nil) -> SearchResult {
        var title: [String: Any] = ["id": id, "name": name, "mediaType": type]
        if let year { title["year"] = year }
        var json: [String: Any] = ["title": title]
        if let score { json["score"] = score }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(SearchResult.self, from: data)
    }

    func testSortsByScoreKeepingArrivalOrderForTies() {
        let merged = SearchRanking.merge([
            result("m1", "Batman Begins", "movie", score: 80),
            result("m2", "The Batman", "movie", score: 90),
            result("s1", "Batman", "series", score: 80),
        ], query: "batman")
        XCTAssertEqual(merged.map(\.id), ["m2", "m1", "s1"])
    }

    func testExactPersonMatchLeadsWhateverItsScore() {
        let merged = SearchRanking.merge([
            result("m1", "Tom Hanks: The Nomad", "movie", score: 300),
            result("p1", "Tom Hanks", "person", score: 14),
            result("p2", "Tom Hanks Jr", "person", score: 20),
        ], query: "  tom   HANKS ")
        XCTAssertEqual(merged.map(\.id), ["p1", "m1", "p2"])
    }

    func testDuplicateIDsKeepTheHigherScore() {
        let merged = SearchRanking.merge([
            result("m1", "Old", "movie", score: 10),
            result("m1", "New", "movie", score: 50),
            result("m1", "Lower", "movie", score: 20),
        ], query: "x")
        XCTAssertEqual(merged.map(\.title.name), ["New"])
    }

    func testMissingIDsDedupeByTypeNameAndYear() {
        let merged = SearchRanking.merge([
            result("", "Heat", "movie", score: 1, year: 1995),
            result("", "HEAT", "movie", score: 2, year: 1995),
            result("", "Heat", "series", score: 1, year: 1995),
        ], query: "heat")
        XCTAssertEqual(merged.map(\.title.name), ["HEAT", "Heat"])
    }

    func testNormalizedNameIsNFKCTrimmedCollapsedAndLowercased() {
        XCTAssertEqual(SearchRanking.normalizedName("  Ｔｏｍ\t Hanks \n"), "tom hanks")
    }

    func testSuggestionsAreTheQueryThenUniqueNamesUpToEight() {
        let titles = (1...10).map { result("\($0)", $0 == 2 ? "Batman" : "Title \($0 % 4)", "movie", score: 1).title }
        XCTAssertEqual(SearchRanking.suggestions(query: "Batman", titles: titles),
                       ["Batman", "Title 1", "Title 3", "Title 0", "Title 2"])
        let many = (1...20).map { result("\($0)", "T\($0)", "movie", score: 1).title }
        XCTAssertEqual(SearchRanking.suggestions(query: "q", titles: many).count, 8)
    }

    func testFailureNotices() {
        XCTAssertNil(SearchRanking.failureNotice([]))
        XCTAssertEqual(SearchRanking.failureNotice(["movie", "series", "person"]),
                       "Search couldn’t complete. Please try again.")
        XCTAssertEqual(SearchRanking.failureNotice(["person", "movie"]),
                       "Movie and Actor search is unavailable. Results may be incomplete.")
        XCTAssertEqual(SearchRanking.failureNotice(["series"]),
                       "TV show search is unavailable. Results may be incomplete.")
    }

    func testQueryIsClampedToFortyCharacters() {
        XCTAssertEqual(SearchRanking.clamp(String(repeating: "a", count: 50)).count, 40)
    }
}
