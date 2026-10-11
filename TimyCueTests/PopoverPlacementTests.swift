import XCTest
@testable import TimyCue

final class PopoverPlacementTests: XCTestCase {
    private let container = CGSize(width: 440, height: 800)
    private let size = CGSize(width: 280, height: 200)

    private func place(_ anchors: [CGRect], sizes: [CGSize]? = nil) -> [CGRect] {
        PopoverPlacement.frames(container: container,
                                anchors: anchors,
                                sizes: sizes ?? anchors.map { _ in size },
                                gap: 4,
                                margin: 8)
    }

    private func isInside(_ rect: CGRect) -> Bool {
        rect.minX >= 8 && rect.maxX <= container.width - 8 && rect.minY >= 8 && rect.maxY <= container.height - 8
    }

    func testBelowTheCellWhenThereIsRoom() {
        let cell = CGRect(x: 200, y: 100, width: 58, height: 80)
        let frame = place([cell])[0]
        XCTAssertEqual(frame.minY, cell.maxY + 4, "基本はセルの下（Q11）")
        XCTAssertTrue(isInside(frame))
    }

    func testAboveTheCellWhenBelowDoesNotFit() {
        let cell = CGRect(x: 200, y: 650, width: 58, height: 80)
        let frame = place([cell])[0]
        XCTAssertEqual(frame.maxY, cell.minY - 4, "下に入らなければ上（Q11）")
        XCTAssertTrue(isInside(frame))
    }

    func testStaysInsideHorizontally() {
        let leftCell = CGRect(x: 4, y: 100, width: 58, height: 80)
        let rightCell = CGRect(x: 380, y: 400, width: 58, height: 80)
        let frames = place([leftCell, rightCell])
        XCTAssertTrue(frames.allSatisfy(isInside), "画面の中に収める（Q11）")
    }

    func testTwoPopoversNeverOverlap() {
        // 同じ週の隣どうしの日：どちらも下に出すと重なる
        let first = CGRect(x: 150, y: 100, width: 58, height: 80)
        let second = CGRect(x: 208, y: 100, width: 58, height: 80)
        let frames = place([first, second])
        XCTAssertFalse(frames[0].intersects(frames[1]), "2 つの吹き出しは重ならない（Q11）")
        XCTAssertTrue(frames.allSatisfy(isInside))
        XCTAssertEqual(frames[0].minY, first.maxY + 4, "先に開いた吹き出しはセルの下のまま")
    }

    func testTwoPopoversInDifferentWeeksThatWouldOverlap() {
        // 上の週の吹き出しを下に出すと、下の週の吹き出しとぶつかる配置（ビルド #4 の画面写真と同じ形）
        let first = CGRect(x: 380, y: 260, width: 58, height: 80)
        let second = CGRect(x: 380, y: 440, width: 58, height: 80)
        let frames = place([first, second], sizes: [CGSize(width: 280, height: 120), CGSize(width: 280, height: 260)])
        XCTAssertFalse(frames[0].intersects(frames[1]))
        XCTAssertTrue(frames.allSatisfy(isInside))
    }
}
