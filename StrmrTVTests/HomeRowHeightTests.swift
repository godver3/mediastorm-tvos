import XCTest
@testable import StrmrTV

/// Home row heights: rows without captions keep the gap that clears a
/// focused card's lift, so the card never touches the next row's title.
final class HomeRowHeightTests: XCTestCase {
    func testRowWithoutCaptionsClearsFocusedCard() {
        for scale in CardSize.allCases.map(\.scale) {
            let card = (ShelfRow.baseCardHeight * scale).rounded()
            let overhang = card * (PosterFocusStyle.focusedScale - 1) / 2
            let below = HomeView.rowHeight(cardHeight: card, captions: false)
                - 46 - ShelfRow.liftRoom(cardHeight: card) - card
            XCTAssertGreaterThanOrEqual(below - overhang, 50, "scale \(scale)")
        }
    }

    func testCaptionsAddTheirTextOverTheGap() {
        let card: CGFloat = 338
        XCTAssertEqual(HomeView.rowHeight(cardHeight: card, captions: true)
            - HomeView.rowHeight(cardHeight: card, captions: false), 36)
    }
}
