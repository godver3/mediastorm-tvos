import XCTest
@testable import StrmrTV

final class IrohRouteTests: XCTestCase {
    func testDirect() {
        XCTAssertEqual(IrohRoute(diagnostics: ["connectionGeneration": 1, "selectedPath": "direct"]), .direct)
    }

    func testRelay() {
        XCTAssertEqual(IrohRoute(diagnostics: ["selectedPath": "relay"]), .relay)
    }

    func testUnknownOrMissing() {
        XCTAssertEqual(IrohRoute(diagnostics: ["selectedPath": "unknown"]), .detecting)
        XCTAssertEqual(IrohRoute(diagnostics: [:]), .detecting)
    }
}
