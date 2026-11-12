import XCTest
@testable import StrmrTV

/// A device's own order for Home rows and menu tabs on top of the server's order.
@MainActor
final class DeviceOrderTests: XCTestCase {
    func testEmptySavedOrderKeepsDefaults() {
        XCTAssertEqual(DeviceOrder.apply([], to: ["a", "b", "c"]), ["a", "b", "c"])
    }

    func testSavedOrderWinsAndDropsGoneIDs() {
        XCTAssertEqual(DeviceOrder.apply(["c", "gone", "a", "b"], to: ["a", "b", "c"]), ["c", "a", "b"])
    }

    func testNewIDLandsAfterItsServerPredecessor() {
        // Server added "x" after "b"; the device put "b" first.
        XCTAssertEqual(DeviceOrder.apply(["b", "c", "a"], to: ["a", "b", "x", "c"]), ["b", "x", "c", "a"])
    }

    func testNewIDWithNoPlacedPredecessorGoesFirst() {
        XCTAssertEqual(DeviceOrder.apply(["b", "a"], to: ["x", "a", "b"]), ["x", "b", "a"])
    }

    func testDuplicateSavedIDsCountOnce() {
        XCTAssertEqual(DeviceOrder.apply(["b", "b", "a"], to: ["a", "b"]), ["b", "a"])
    }

    func testMoveTakesTargetsPlace() {
        let order = ["a", "b", "c", "d"]
        XCTAssertEqual(DeviceOrder.move("a", to: "c", in: order), ["b", "c", "a", "d"])
        XCTAssertEqual(DeviceOrder.move("d", to: "b", in: order), ["a", "d", "b", "c"])
        XCTAssertEqual(DeviceOrder.move("b", to: "c", in: order), ["a", "c", "b", "d"])
        XCTAssertEqual(DeviceOrder.move("a", to: "missing", in: order), order)
    }

    func testShelfOrderKeepsPromotedTopTenFirst() {
        let defaults = UserDefaults(suiteName: "DeviceOrderTests")!
        defaults.removePersistentDomain(forName: "DeviceOrderTests")
        let store = ShelfOrderStore(defaults: defaults)
        let ids = [HomeShelf.promotedTopTenID, "a", "b"]
        store.move("b", to: HomeShelf.promotedTopTenID, in: ids)
        XCTAssertEqual(store.ordered(ids, id: { $0 }), [HomeShelf.promotedTopTenID, "b", "a"])
        XCTAssertEqual(ShelfOrderStore(defaults: defaults).order, store.order, "saved across launches")
        store.reset()
        XCTAssertEqual(store.ordered(ids, id: { $0 }), ids)
    }

    func testMenuTabOrderSaved() {
        let defaults = UserDefaults(suiteName: "DeviceOrderTabs")!
        defaults.removePersistentDomain(forName: "DeviceOrderTabs")
        let store = MenuTabsStore(defaults: defaults)
        store.moveTab("search", to: "watchlist", in: ["watchlist", "lists", "search"])
        XCTAssertEqual(MenuTabsStore(defaults: defaults).order, ["search", "watchlist", "lists"])
        store.resetTabOrder()
        XCTAssertTrue(store.order.isEmpty)
    }
}
