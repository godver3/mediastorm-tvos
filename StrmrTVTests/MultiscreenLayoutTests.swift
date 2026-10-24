import XCTest
@testable import StrmrTV

/// `MultiscreenLayout`: the Expo app's `multiscreenFrames` / `multiscreenNeighbor`.
final class MultiscreenLayoutTests: XCTestCase {
    private let size = CGSize(width: 1824, height: 952)
    private let gap: CGFloat = 12

    private func assertSixteenNine(_ rect: CGRect?, file: StaticString = #filePath, line: UInt = #line) {
        guard let rect else { return XCTFail("missing frame", file: file, line: line) }
        XCTAssertEqual(rect.width * 9 / 16, rect.height, accuracy: 0.01, file: file, line: line)
    }

    func testNoTilesNoFrames() {
        XCTAssertTrue(MultiscreenLayout.frames([], expanded: nil, size: size, gap: gap).isEmpty)
    }

    func testOneTileFillsTheArea() {
        let frames = MultiscreenLayout.frames([2], expanded: nil, size: size, gap: gap)
        XCTAssertEqual(frames, [2: CGRect(origin: .zero, size: size)])
    }

    func testTwoTilesSideBySideCentred() {
        let frames = MultiscreenLayout.frames([0, 1], expanded: nil, size: size, gap: gap)
        let a = frames[0]!, b = frames[1]!
        XCTAssertEqual(a.width, (size.width - gap) / 2, accuracy: 0.01)
        XCTAssertEqual(b.minX - a.maxX, gap, accuracy: 0.01)
        XCTAssertEqual(a.minY, b.minY)
        XCTAssertEqual(a.midY, size.height / 2, accuracy: 0.01)
        assertSixteenNine(a)
    }

    func testThreeTilesInATwoByTwoGrid() {
        let frames = MultiscreenLayout.frames([0, 1, 3], expanded: nil, size: size, gap: gap)
        XCTAssertEqual(frames[0]!.minY, frames[1]!.minY)
        XCTAssertEqual(frames[3]!.minX, frames[0]!.minX, "keyed by slot: slot 3 is the third tile")
        XCTAssertEqual(frames[3]!.minY - frames[0]!.maxY, gap, accuracy: 0.01)
        XCTAssertLessThanOrEqual(frames[3]!.maxY, size.height + 0.01)
        frames.values.forEach { assertSixteenNine($0) }
    }

    func testEnlargedPairSitsSideBySide() {
        let frames = MultiscreenLayout.frames([0, 1], expanded: 1, size: size, gap: gap)
        let small = frames[0]!, large = frames[1]!
        XCTAssertEqual(large.width, min((size.width - gap) * 0.72, size.height * 16 / 9), accuracy: 0.01)
        XCTAssertLessThan(small.width, large.width)
        XCTAssertEqual(large.minX - small.maxX, gap, accuracy: 0.01, "the small one is first, on the left")
        XCTAssertEqual(small.midY, large.midY, accuracy: 0.01)
        assertSixteenNine(small)
        assertSixteenNine(large)
    }

    func testEnlargedTileWithAColumnBesideIt() {
        let frames = MultiscreenLayout.frames([0, 1, 2, 3], expanded: 2, size: size, gap: gap)
        let large = frames[2]!
        XCTAssertEqual(large.minX, frames.values.map(\.minX).min()!)
        for id in [0, 1, 3] {
            XCTAssertGreaterThanOrEqual(frames[id]!.minX, large.maxX + gap - 0.01)
            XCTAssertLessThanOrEqual(frames[id]!.maxX, size.width + 0.01)
            assertSixteenNine(frames[id])
        }
        XCTAssertLessThan(frames[0]!.minY, frames[1]!.minY)
        XCTAssertLessThan(frames[1]!.minY, frames[3]!.minY)
    }

    func testExpandedNotOnScreenFallsBackToTheGrid() {
        XCTAssertEqual(MultiscreenLayout.frames([0, 1], expanded: 3, size: size, gap: gap),
                       MultiscreenLayout.frames([0, 1], expanded: nil, size: size, gap: gap))
    }

    func testNeighborInTheGrid() {
        let frames = MultiscreenLayout.frames([0, 1, 2, 3], expanded: nil, size: size, gap: gap)
        XCTAssertEqual(MultiscreenLayout.neighbor(frames, of: 0, .right), 1)
        XCTAssertEqual(MultiscreenLayout.neighbor(frames, of: 0, .down), 2)
        XCTAssertEqual(MultiscreenLayout.neighbor(frames, of: 3, .up), 1)
        XCTAssertEqual(MultiscreenLayout.neighbor(frames, of: 3, .left), 2)
        XCTAssertNil(MultiscreenLayout.neighbor(frames, of: 2, .down))
        XCTAssertNil(MultiscreenLayout.neighbor(frames, of: 0, .left))
        XCTAssertNil(MultiscreenLayout.neighbor(frames, of: 9, .left))
    }

    func testNeighborPrefersTheAlignedTile() {
        // Lone tile in the second row, under the left of the first.
        let frames = MultiscreenLayout.frames([0, 1, 2], expanded: nil, size: size, gap: gap)
        XCTAssertEqual(MultiscreenLayout.neighbor(frames, of: 2, .up), 0)
        XCTAssertEqual(MultiscreenLayout.neighbor(frames, of: 1, .down), 2)
    }

    func testNeighborAcrossTheEnlargedTile() {
        let frames = MultiscreenLayout.frames([0, 1, 2, 3], expanded: 0, size: size, gap: gap)
        XCTAssertEqual(MultiscreenLayout.neighbor(frames, of: 0, .right), 2, "the side tile nearest the large one's centre")
        XCTAssertEqual(MultiscreenLayout.neighbor(frames, of: 3, .left), 0)
        XCTAssertEqual(MultiscreenLayout.neighbor(frames, of: 1, .down), 2)
        XCTAssertNil(MultiscreenLayout.neighbor(frames, of: 0, .down))
    }
}
