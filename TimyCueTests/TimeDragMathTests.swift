import XCTest
@testable import TimyCue

final class TimeDragMathTests: XCTestCase {
    private let hourHeight = 44.0

    func testWheelStartsAtZeroMinutes() {
        XCTAssertEqual(TimeDragMath.startMinute(hour: 14, minute: 0), 14 * 60, "「時」を押すと 00 分から（§38）")
        XCTAssertEqual(TimeDragMath.startMinute(hour: 14, minute: 17), 14 * 60 + 17, "14:00 → 14:17")
        XCTAssertEqual(TimeDragMath.startMinute(hour: 23, minute: 59), 23 * 60 + 59)
    }

    func testDraggingDraftChangesStartByFiveMinutes() {
        // 44pt で 1 時間 → 11pt で 15 分
        XCTAssertEqual(TimeDragMath.startMinute(afterDragging: 11, from: 14 * 60, hourHeight: hourHeight), 14 * 60 + 15)
        XCTAssertEqual(TimeDragMath.startMinute(afterDragging: 27.1, from: 14 * 60, hourHeight: hourHeight), 14 * 60 + 35,
                       "動かすのも 5 分おき（36.95 分 → 14:35。2026-10-14 ユーザー決定）")
        XCTAssertEqual(TimeDragMath.startMinute(afterDragging: -44, from: 14 * 60, hourHeight: hourHeight), 13 * 60)
        XCTAssertEqual(TimeDragMath.startMinute(afterDragging: 0.5, from: 14 * 60 + 37, hourHeight: hourHeight), 14 * 60 + 40,
                       "前の時刻が 5 分おきでなくても、動かせば 5 分おきにそろう")
    }

    func testDraggingStaysWithinTheDay() {
        XCTAssertEqual(TimeDragMath.startMinute(afterDragging: -1000, from: 60, hourHeight: hourHeight), 0)
        XCTAssertEqual(TimeDragMath.startMinute(afterDragging: 5000, from: 23 * 60, hourHeight: hourHeight), 23 * 60 + 55,
                       "いちばん遅くて 23:55")
    }

    func testEndHandleSnapsToFiveMinutesOnTheClock() {
        // 44pt で 1 時間。8pt ≒ 10.9 分 → 15:10、10pt ≒ 13.6 分 → 15:15（時計の 5 分おき。2026-10-14 実機の指摘。刻みは仮）
        XCTAssertEqual(TimeDragMath.endMinute(afterDragging: 8, from: 15 * 60, start: 14 * 60, hourHeight: hourHeight), 15 * 60 + 10)
        XCTAssertEqual(TimeDragMath.endMinute(afterDragging: 10, from: 15 * 60, start: 14 * 60, hourHeight: hourHeight), 15 * 60 + 15)
        XCTAssertEqual(TimeDragMath.endMinute(afterDragging: 0.5, from: 15 * 60 + 7, start: 14 * 60, hourHeight: hourHeight), 15 * 60 + 10,
                       "前の終了が 5 分おきでなくても、伸ばせば 5 分おきにそろう")
        XCTAssertEqual(TimeDragMath.endMinute(afterDragging: -200, from: 15 * 60, start: 14 * 60 + 37, hourHeight: hourHeight),
                       14 * 60 + 37 + TimeDragMath.minimumDuration, "いちばん短くても開始の 5 分後")
    }

    func testEndHandle() {
        XCTAssertEqual(TimeDragMath.endMinute(afterDragging: 11, from: 15 * 60, start: 14 * 60, hourHeight: hourHeight), 15 * 60 + 15,
                       "下端を伸ばすと終了が後ろへ（§41）")
        XCTAssertEqual(TimeDragMath.endMinute(afterDragging: -200, from: 15 * 60, start: 14 * 60, hourHeight: hourHeight),
                       14 * 60 + TimeDragMath.minimumDuration, "開始より前には縮めない")
        XCTAssertEqual(TimeDragMath.endMinute(afterDragging: 5000, from: 23 * 60, start: 22 * 60, hourHeight: hourHeight), 24 * 60,
                       "24:00 まで")
    }

    @MainActor
    func testHandleSetsTheEnd() {
        let day = CalendarDay(year: 2026, month: 10, day: 12)
        let store = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository())
        store.startNew(on: day)
        store.setStartMinute(14 * 60)
        // 下端のハンドルを伸ばす（14:20 から 75 分ぶん下へ）。終了は下端のハンドルだけで決める（「終了」の行はなくした。2026-10-14）
        store.setEndMinute(TimeDragMath.endMinute(afterDragging: 55, from: 14 * 60 + 20, start: 14 * 60, hourHeight: hourHeight), on: day)
        XCTAssertEqual(store.durationMinutes(on: day), 95)
        XCTAssertEqual(store.endMinute(on: day), 15 * 60 + 35)
        XCTAssertFalse(InputRow.allCases.map(\.label).contains("終了"))
    }

    func testStartWheelIsEveryFiveMinutesAcrossHours() {
        let values = TimeDragMath.wheelMinutes
        XCTAssertEqual(values.count, 24 * 12, "0:00〜23:55 を 5 分おき（2026-10-13 実機の指摘）")
        let nine55 = values.firstIndex(of: 9 * 60 + 55)!
        XCTAssertEqual(values[nine55 + 1], 10 * 60, "9:55 の次は 10:00（0 分をまたぐと時も変わる）")
        XCTAssertEqual(values[nine55 - 11], 9 * 60, "上へ戻れば 9:00、さらに上は 8 時台")
    }
}
