import XCTest
@testable import TimyCue

final class EditorCalendarAxisTests: XCTestCase {
    private let axis = EditorCalendarAxis(around: CalendarMonth(year: 2026, month: 10))

    func testOriginIsWeekContainingFirstDayOfMonth() {
        XCTAssertEqual(axis.week(at: 0).days.map(\.day), [28, 29, 30, 1, 2, 3, 4], "週は途切れず続く（v1.1）")
        XCTAssertEqual(axis.topWeek(at: 0.6), axis.week(at: 0), "途中までスクロールしていても、いちばん上の週は番号の小数を切り捨てた週")
        XCTAssertEqual(axis.topWeek(at: -0.2), axis.week(at: -1))
    }

    func testJumpPutsFirstWeekOfMonthOnTop() {
        let offset = axis.offset(jumpingTo: CalendarMonth(year: 2026, month: 12))
        XCTAssertEqual(axis.topWeek(at: offset), CalendarWeek(containing: CalendarDay(year: 2026, month: 12, day: 1)),
                       "その月の 1 日を含む週がいちばん上の列に来る（v1.1「年月バーのタップ」）")
        XCTAssertEqual(axis.offset(jumpingTo: CalendarMonth(year: 2026, month: 9)), -4, "9 月 1 日を含む週は 4 週前")
    }

    func testDayAtPoint() {
        // 行の高さ 40、列の幅 50、いちばん上は番号 0 の週
        XCTAssertEqual(axis.day(atX: 10, y: 5, offset: 0, rowHeight: 40, columnWidth: 50),
                       CalendarDay(year: 2026, month: 9, day: 28))
        XCTAssertEqual(axis.day(atX: 320, y: 45, offset: 0, rowHeight: 40, columnWidth: 50),
                       CalendarDay(year: 2026, month: 10, day: 11), "2 行目の日曜")
        XCTAssertEqual(axis.day(atX: 10, y: 5, offset: 0.5, rowHeight: 40, columnWidth: 50),
                       CalendarDay(year: 2026, month: 9, day: 28), "半分スクロールしている：上の行の下半分")
        XCTAssertEqual(axis.day(atX: 10, y: 25, offset: 0.5, rowHeight: 40, columnWidth: 50),
                       CalendarDay(year: 2026, month: 10, day: 5), "その下の行")
        XCTAssertNil(axis.day(atX: 10, y: -1, offset: 0, rowHeight: 40, columnWidth: 50))
    }

    func testBarMonthsAndLabelPositions() {
        let months = axis.barMonths(offset: 0, spanWeeks: 10)
        XCTAssertEqual(months.map(\.month.monthLabel), ["8月", "9月", "10月", "11月", "12月"])
        XCTAssertEqual(months.first { $0.month.month == 10 }?.weekIndex, 0)
        // 年月バーの固定帯の上端に、いちばん上に見えている週が来る
        XCTAssertEqual(EditorCalendarAxis.barY(weekIndex: 0, offset: 0, bandTop: 100, weekHeight: 7), 100)
        XCTAssertEqual(EditorCalendarAxis.barY(weekIndex: 0, offset: 2, bandTop: 100, weekHeight: 7), 86,
                       "下の月へ進むと、ラベルが固定帯の下を上へ流れる（帯は動かない）")
    }

    func testDecemberToJanuaryCrossesYearOnOneAxis() {
        let months = axis.barMonths(offset: axis.offset(jumpingTo: CalendarMonth(year: 2027, month: 1)), spanWeeks: 6)
        XCTAssertTrue(months.contains { $0.month == CalendarMonth(year: 2026, month: 12) })
        XCTAssertTrue(months.contains { $0.month == CalendarMonth(year: 2027, month: 1) },
                      "年と月は 1 本の続いた縦軸（v1.1）")
        let january = axis.offset(jumpingTo: CalendarMonth(year: 2027, month: 1))
        XCTAssertEqual(axis.topWeek(at: january).stickyMonth.year, 2027, "1 月の週が上に来たら年が変わる（ハプティクスの合図）")
        XCTAssertEqual(axis.topWeek(at: january - 1).stickyMonth.year, 2026)
    }

    func testHoldingAboveOrBelowTheBandMovesSlowly() {
        XCTAssertEqual(EditorCalendarAxis.holdDirection(pressY: 40, barHeight: 300), -1, "範囲帯より上を長押しすると上（過去）へ")
        XCTAssertEqual(EditorCalendarAxis.holdDirection(pressY: 260, barHeight: 300), 1, "下を長押しすると下（未来）へ")
        let speed = Double(EditorMetrics.barHoldWeeksPerSecond)
        XCTAssertEqual(EditorCalendarAxis.offset(afterHolding: 2, from: 10, direction: -1, weeksPerSecond: speed), 10 - 2 * speed,
                       "押している間ずっと一定の速さ")
        XCTAssertEqual(EditorCalendarAxis.offset(afterHolding: 0.5, from: 10, direction: 1, weeksPerSecond: speed), 10 + 0.5 * speed,
                       "月にはスナップしない")
    }

    func testSafetyLimit() {
        XCTAssertEqual(axis.clamp(1_000_000), Double(EditorCalendarAxis.maxWeeks))
        XCTAssertEqual(axis.clamp(-1_000_000), -Double(EditorCalendarAxis.maxWeeks))
    }
}

@MainActor
final class EditorScreenStoreTests: XCTestCase {
    private let d1 = CalendarDay(year: 2026, month: 10, day: 12)
    private let d2 = CalendarDay(year: 2026, month: 10, day: 19)

    func testRowTexts() {
        let store = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository())
        store.startNew(on: d1)
        XCTAssertEqual(store.valueText(for: .title), "未入力")
        XCTAssertEqual(store.valueText(for: .location), "なし")
        XCTAssertEqual(store.valueText(for: .arrivalTarget), "未設定")
        XCTAssertEqual(store.valueText(for: .transport), "自動")
        XCTAssertEqual(store.valueText(for: .notifications), "30分・10分・出発")
        XCTAssertEqual(store.valueText(for: .end), "未設定")

        store.content.title = "A社"
        store.content.metadata.arrivalTargetMinutes = 10
        store.setStartMinute(600)
        store.setDuration(90)
        XCTAssertEqual(store.valueText(for: .title), "A社")
        XCTAssertEqual(store.valueText(for: .arrivalTarget), "10分前", "§44 の例のとおり")
        XCTAssertEqual(store.valueText(for: .end), "11:30")
        store.setDuration(nil)
        XCTAssertEqual(store.valueText(for: .end), "未設定")
    }

    func testDeleteEditingEvent() throws {
        let event = CalendarEvent(day: d1, startMinute: 600, title: "A社")
        let events = InMemoryEventRepository(events: [event])
        let metadata = InMemoryEventMetadataRepository(metadata: [event.id: TimyCueEventMetadata()])
        let store = ScheduleEditorStore(repository: events, metadataRepository: metadata)
        try store.startEditing(eventID: event.id)
        try store.deleteEditingEvent()
        XCTAssertTrue(events.allEvents().isEmpty, "予定を削除（§64）")
        XCTAssertNil(metadata.allMetadata()[event.id], "TimyCue の情報も消す")
        XCTAssertEqual(store.mode, .new)
    }

    func testRefreshPicksUpEventsAddedElsewhere() throws {
        let events = InMemoryEventRepository()
        let store = ScheduleEditorStore(repository: events, metadataRepository: InMemoryEventMetadataRepository())
        let added = CalendarEvent(day: d2, startMinute: 600, title: "あとから")
        try events.insert([added])
        XCTAssertThrowsError(try store.startEditing(eventID: added.id))
        store.refresh()
        XCTAssertNoThrow(try store.startEditing(eventID: added.id))
    }
}
