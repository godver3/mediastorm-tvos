import XCTest
@testable import StrmrTV

/// The Carousel Home style's row choice: the chosen row, else Top 10, else
/// Trending, else the first row with titles; a preferred row still loading holds the carousel.
@MainActor
final class HomeCarouselSourceTests: XCTestCase {
    private func card(_ id: String) -> HomeCard {
        let target = DetailsTarget(titleID: id, name: id, isMovie: true, year: 2026, tmdbID: nil, imdbID: nil,
                                   tvdbID: nil, posterURL: nil, textPosterURL: nil, backdropURL: nil,
                                   logoURL: nil, overview: nil)
        return HomeCard(id: id, target: target, title: id, subtitle: "", overview: nil, artworkURL: nil)
    }

    private func shelf(_ id: String, count: Int = 3) -> HomeSlot {
        .shelf(HomeShelf(id: id, title: id, cards: (0..<count).map { card("\(id)-\($0)") }))
    }

    /// A row of Watch Something actions: nothing for the carousel to open.
    private var actions: HomeSlot {
        .shelf(HomeShelf(id: "watch-something", title: "Watch Something",
                         cards: [HomeCard(id: "search", link: .action(.search), title: "Search", subtitle: "")]))
    }

    func testDefaultPrefersTopTenThenTrending() {
        let slots = [actions, shelf("continue-watching"), shelf("trending-tv"), shelf("top-ten")]
        XCTAssertEqual(HomeCarouselSource.resolve(slots: slots, chosen: nil).id, "top-ten")
        let noTopTen = [shelf("continue-watching"), shelf("trending-tv"), shelf("trending-movies")]
        XCTAssertEqual(HomeCarouselSource.resolve(slots: noTopTen, chosen: nil).id, "trending-movies")
    }

    func testChosenRowWinsAndFallsBackWhenAbsent() {
        let slots = [shelf("continue-watching"), shelf("top-ten")]
        XCTAssertEqual(HomeCarouselSource.resolve(slots: slots, chosen: "continue-watching").id, "continue-watching")
        XCTAssertEqual(HomeCarouselSource.resolve(slots: slots, chosen: "gone").id, "top-ten")
    }

    func testFirstRowWithTitlesSkipsActionRows() {
        let source = HomeCarouselSource.resolve(slots: [actions, shelf("my-list")], chosen: "watch-something")
        XCTAssertEqual(source.id, "my-list")
    }

    func testLoadingPreferredRowHoldsTheCarousel() {
        let slots: [HomeSlot] = [.loading(id: "top-ten", title: "Top 10"), shelf("trending-movies")]
        let source = HomeCarouselSource.resolve(slots: slots, chosen: nil)
        XCTAssertEqual(source.id, "top-ten")
        XCTAssertNil(source.shelf)
    }

    func testAtMostTenSlides() {
        guard case let .shelf(row) = shelf("top-ten", count: 14) else { return XCTFail() }
        XCTAssertEqual(HomeCarouselSource.slides(row).count, HomeCarouselSource.maxSlides)
    }

    func testDefaultRowForSettings() {
        XCTAssertEqual(HomeStyleStore.defaultRow(in: ["continue-watching", "trending-tv"]), "trending-tv")
        XCTAssertEqual(HomeStyleStore.defaultRow(in: ["continue-watching"]), "continue-watching")
        XCTAssertNil(HomeStyleStore.defaultRow(in: []))
    }
}
