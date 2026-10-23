import XCTest
@testable import StrmrTV

/// `ensureHomeShelfConfig` as Home views apply it to the layout they inherit.
final class HomeShelfDefaultsTests: XCTestCase {
    private func shelf(_ id: String, enabled: Bool = true, order: Int, _ extra: [String: Any] = [:]) -> ShelfConfig {
        ShelfConfig.make(["id": id, "name": id, "enabled": enabled, "order": order].merging(extra) { _, new in new })!
    }

    func testEmptyListIsTheDefaults() {
        XCTAssertEqual(HomeShelfDefaults.ensure([]).map(\.id), HomeShelfDefaults.shelves.map(\.id))
        XCTAssertEqual(HomeShelfDefaults.shelves.count, 19)
    }

    func testCompleteListOnlyMovesWatchTogetherAndTurnsTonightOff() {
        var shelves = HomeShelfDefaults.shelves.filter { $0.id != "watch-together" }
        shelves = shelves.map { $0.id == "tonight" ? $0.with(enabled: true) : $0 } + [shelves[0]]
        let ensured = HomeShelfDefaults.ensure(shelves)
        XCTAssertEqual(ensured.first?.id, "watch-together")
        XCTAssertEqual(ensured.first?.order, -1)
        XCTAssertEqual(ensured.count, HomeShelfDefaults.shelves.count)
        XCTAssertEqual(ensured.first { $0.id == "tonight" }?.enabled, false)
        XCTAssertEqual(ensured.dropFirst().map(\.order), shelves.dropLast().map(\.order))
    }

    func testFillsMissingBuiltInsAfterTheShelfTheyFollow() {
        let ensured = HomeShelfDefaults.ensure([shelf("continue-watching", order: 0), shelf("watchlist", order: 1)])
        func order(_ id: String) -> Int? { ensured.first { $0.id == id }?.order }
        // Worked through by hand from the TypeScript (each insert shifts the orders at or after it).
        XCTAssertEqual(order("continue-watching"), 0)
        XCTAssertEqual(order("watch-something"), 1)
        XCTAssertEqual(order("tonight"), 2)
        XCTAssertEqual(order("my-recommended"), 3)
        XCTAssertEqual(order("my-upcoming"), 4)
        XCTAssertEqual(order("calendar"), 5)
        XCTAssertEqual(order("my-recently-aired"), 6)
        XCTAssertEqual(order("watchlist"), 7)
        XCTAssertEqual(order("streaming-services"), 8)
        XCTAssertEqual(order("live-favorites"), 9)
        XCTAssertEqual(order("dashboard"), 10)
        XCTAssertEqual(order("permanent-prequeue"), 11)
        XCTAssertEqual(order("set-aside"), 12)
        XCTAssertEqual(ensured.first { $0.id == "my-upcoming" }?.sort, "air-date-asc")
        XCTAssertEqual(ensured.first { $0.id == "tonight" }?.enabled, false)
    }

    func testKeepsLegacyRecommendationsAndSortsUpcoming() {
        let ensured = HomeShelfDefaults.ensure([shelf("gemini-recs", order: 0), shelf("my-upcoming", order: 1)])
        XCTAssertFalse(ensured.contains { $0.id == "my-recommended" })
        XCTAssertEqual(ensured.first { $0.id == "my-upcoming" }?.sort, "air-date-asc")
    }

    func testDropsDuplicateIDs() {
        let ensured = HomeShelfDefaults.ensure([shelf("watchlist", order: 0), shelf("watchlist", enabled: false, order: 5)])
        XCTAssertEqual(ensured.filter { $0.id == "watchlist" }.count, 1)
        XCTAssertEqual(ensured.first { $0.id == "watchlist" }?.enabled, true)
    }
}
