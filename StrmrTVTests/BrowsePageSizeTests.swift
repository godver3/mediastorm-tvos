import XCTest
@testable import StrmrTV

/// A Lists grid pages until the list ends. The server returns short pages mid-list (TMDB
/// genre and decade pages are capped at 50 against the grid's 60; hidden titles are dropped
/// after the read), so a short page must not end the list: the 2000s decade stopped at 50.
final class BrowsePageSizeTests: XCTestCase {
    private func page(_ count: Int, total: Int) throws -> BrowsePage {
        let titles = try (0..<count).map { i in
            try JSONDecoder().decode(Title.self, from: Data(#"{"id":"t\#(i)","name":"Title \#(i)","mediaType":"movie"}"#.utf8))
        }
        return BrowsePage(entries: titles.map(BrowseEntry.title), total: total)
    }

    func testShortPageMidListKeepsTheTotal() throws {
        XCTAssertEqual(try page(50, total: 500).listSize(fetched: 50), 500)
    }

    func testEmptyPageEndsTheList() throws {
        XCTAssertEqual(try page(0, total: 500).listSize(fetched: 180), 180)
    }

    func testTotalBelowWhatWasReadEndsAtWhatWasRead() throws {
        XCTAssertEqual(try page(47, total: 40).listSize(fetched: 47), 47)
    }
}
