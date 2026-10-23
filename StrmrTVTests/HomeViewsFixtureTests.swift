import XCTest
@testable import StrmrTV

/// The Swift port against the Expo client's own code: `HomeViewsFixture` holds the inputs
/// in `scripts/home-views-cases.mts` and what the TypeScript made of them
/// (`scripts/gen-home-views-fixture.sh`).
final class HomeViewsFixtureTests: XCTestCase {
    private var fixture: [String: Any] = [:]

    override func setUpWithError() throws {
        fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(HomeViewsFixture.json.utf8)) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ value: Any?) throws -> T? {
        guard let value, !(value is NSNull) else { return nil }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }

    /// A shelf as the fixture lists it: id, enabled, order, sort.
    private func row(_ shelf: ShelfConfig) -> [String] {
        [shelf.id, "\(shelf.enabled == true)", "\(shelf.order ?? 0)", shelf.sort ?? "-"]
    }

    private func rows(_ expected: Any?) -> [[String]] {
        (expected as? [[Any]] ?? []).map { item in
            [item[0] as? String ?? "", "\((item[1] as? Bool) == true)", "\((item[2] as? Int) ?? 0)", item[3] as? String ?? "-"]
        }
    }

    func testResolveMatchesExpo() throws {
        let inputs = try XCTUnwrap(fixture["inputs"] as? [String: [Any]])
        XCTAssertGreaterThan((fixture["resolve"] as? [Any])?.count ?? 0, 20)
        for case let item as [String: Any] in fixture["resolve"] as? [Any] ?? [] {
            let name = try XCTUnwrap(item["name"] as? String), view = try XCTUnwrap(item["view"] as? String)
            let pair = try XCTUnwrap(inputs[name])
            let global = try decode(HomeShelvesConfig.self, pair.first)
            let profile = try decode(HomeShelvesConfig.self, pair.count > 1 ? pair[1] : nil)
            let resolved = HomeViews.resolve(global: global, profile: profile, view: view)
            let expected = try XCTUnwrap(item["expected"] as? [String: Any])
            let label = "\(name) / \(view)"
            XCTAssertEqual((resolved.shelves ?? []).map(row), rows(expected["shelves"]), label)
            XCTAssertEqual(resolved.itemCap, expected["itemCap"] as? Int, label)
            XCTAssertEqual(resolved.tvTopShelfMode, expected["tvTopShelfMode"] as? String, label)
            XCTAssertEqual(resolved.tvTopShelfSourceId, expected["tvTopShelfSourceId"] as? String, label)
        }
    }

    func testEnsureMatchesExpo() throws {
        XCTAssertGreaterThan((fixture["ensure"] as? [Any])?.count ?? 0, 4)
        for case let item as [String: Any] in fixture["ensure"] as? [Any] ?? [] {
            let input = try XCTUnwrap(try decode([ShelfConfig].self, item["input"]))
            XCTAssertEqual(HomeShelfDefaults.ensure(input).map(row), rows(item["expected"]), input.map(\.id).joined(separator: ","))
        }
    }

    func testViewIDsAndFiltersMatchExpo() throws {
        for case let item as [String: Any] in fixture["ids"] as? [Any] ?? [] {
            let merged = HomeViews.merge(try decode(HomeViewDefinitions.self, item["global"]),
                                         try decode(HomeViewDefinitions.self, item["profile"]))
            XCTAssertEqual(HomeViews.ids(merged), item["expected"] as? [String])
            for (id, filter) in item["filters"] as? [String: String] ?? [:] {
                XCTAssertEqual(HomeViews.filter(id, merged).rawValue, filter, id)
            }
        }
    }

    func testMatchesAndShelfFilterMatchExpo() throws {
        XCTAssertGreaterThan((fixture["allowed"] as? [Any])?.count ?? 0, 10)
        for case let item as [Any] in fixture["matches"] as? [Any] ?? [] {
            let type = item[0] as? String
            XCTAssertEqual(HomeViews.matches(mediaType: type, .movies), item[1] as? Bool, type ?? "")
            XCTAssertEqual(HomeViews.matches(mediaType: type, .shows), item[2] as? Bool, type ?? "")
        }
        for case let item as [Any] in fixture["allowed"] as? [Any] ?? [] {
            let shelf = try XCTUnwrap(try decode(ShelfConfig.self, item[0]))
            XCTAssertEqual(HomeViews.shelfAllowed(shelf, .movies), item[1] as? Bool, shelf.id)
            XCTAssertEqual(HomeViews.shelfAllowed(shelf, .shows), item[2] as? Bool, shelf.id)
            XCTAssertEqual(HomeViews.shelfAllowed(shelf, .all), item[3] as? Bool, shelf.id)
        }
    }
}
