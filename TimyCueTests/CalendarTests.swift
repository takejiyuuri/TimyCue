import XCTest
@testable import TimyCue

final class CalendarMonthTests: XCTestCase {
    func testWeeksStartOnMonday() {
        // 2026 年 10 月 1 日は木曜
        let weeks = CalendarMonth(year: 2026, month: 10).weeks()
        XCTAssertEqual(weeks.count, 5)
        XCTAssertEqual(weeks.first?.map { $0?.day }, [nil, nil, nil, 1, 2, 3, 4], "月曜始まり（仕様 §19）")
        XCTAssertEqual(weeks.last?.map { $0?.day }, [26, 27, 28, 29, 30, 31, nil])
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
    }

    func testFebruaryAndLeapYear() {
        XCTAssertEqual(CalendarMonth(year: 2027, month: 2).numberOfDays(), 28)
        XCTAssertEqual(CalendarMonth(year: 2028, month: 2).numberOfDays(), 29)
    }

    func testAddingMonthsAcrossYears() {
        XCTAssertEqual(CalendarMonth(year: 2026, month: 12).adding(months: 1), CalendarMonth(year: 2027, month: 1))
        XCTAssertEqual(CalendarMonth(year: 2026, month: 1).adding(months: -1), CalendarMonth(year: 2025, month: 12))
        XCTAssertEqual(CalendarMonth(year: 2026, month: 10).adding(months: 24), CalendarMonth(year: 2028, month: 10))
    }

    func testRangeIsContinuous() {
        let months = CalendarMonth.range(around: CalendarMonth(year: 2026, month: 10), before: 2, after: 3)
        XCTAssertEqual(months.map(\.title), ["2026年8月", "2026年9月", "2026年10月", "2026年11月", "2026年12月", "2027年1月"])
    }

    func testWeekdaySymbol() {
        XCTAssertEqual(CalendarDay(year: 2026, month: 10, day: 11).weekdaySymbol(), "日")
        XCTAssertEqual(CalendarDay(year: 2026, month: 10, day: 12).weekdaySymbol(), "月")
    }

    func testDaysAreCountedInGregorianCalendar() {
        XCTAssertEqual(Calendar.timyCue.identifier, .gregorian, "端末が和暦でも西暦で数える")
    }
}

final class DayCellSummaryTests: XCTestCase {
    private func marks(_ count: Int) -> [EventMark] {
        (0..<count).map { EventMark(title: "予定\($0)", color: EventColor.allCases[$0 % EventColor.allCases.count]) }
    }

    func testTitlesUpToFour() {
        XCTAssertEqual(DayCellSummary(marks: []), .empty)
        XCTAssertEqual(DayCellSummary(marks: marks(1)), .titles(marks(1)))
        XCTAssertEqual(DayCellSummary(marks: marks(4)), .titles(marks(4)), "1〜4 件は 色点＋予定名（仕様 §21）")
    }

    func testDotsFromFiveToTwelve() {
        let five = DayCellSummary(marks: marks(5))
        XCTAssertEqual(five, .dots(marks(5).map { .dot($0.color) }), "5 件から色点だけ")
        XCTAssertEqual(five.dotRows.map(\.count), [3, 2])

        let twelve = DayCellSummary(marks: marks(12))
        XCTAssertEqual(twelve.dotRows.map(\.count), [3, 3, 3, 3], "縦 4 × 横 3 の 12 枠")
        XCTAssertFalse(twelve.dotRows.joined().contains { if case .more = $0 { true } else { false } })
    }

    func testThirteenOrMoreShowsElevenDotsAndPlusN() {
        let thirteen = DayCellSummary(marks: marks(13))
        let rows = thirteen.dotRows
        XCTAssertEqual(rows.map(\.count), [3, 3, 3, 3])
        XCTAssertEqual(rows.last?.last, .more(2), "13 件なら 11 件まで色点、12 枠目に +2（仕様 §21）")

        let twenty = DayCellSummary(marks: marks(20))
        XCTAssertEqual(twenty.dotRows.joined().last, .more(9))
        XCTAssertEqual(twenty.dotRows.joined().count, 12)
    }
}

@MainActor
final class CalendarStoreTests: XCTestCase {
    private let today = CalendarDay(year: 2026, month: 10, day: 12)

    private func makeStore(_ events: [CalendarEvent], metadata: [UUID: TimyCueEventMetadata] = [:]) -> CalendarStore {
        CalendarStore(repository: InMemoryEventRepository(events: events),
                      metadataRepository: InMemoryEventMetadataRepository(metadata: metadata),
                      today: today)
    }

    func testMonthsAroundToday() {
        let store = makeStore([])
        XCTAssertEqual(store.currentMonth, CalendarMonth(year: 2026, month: 10))
        XCTAssertEqual(store.months.first, CalendarMonth(year: 2025, month: 10))
        XCTAssertEqual(store.months.last, CalendarMonth(year: 2028, month: 10))
        XCTAssertEqual(store.months, store.months.sorted(), "月は縦に順につながる（仕様 §19）")
    }

    func testEventsAreAllDayFirstThenByStartTime() {
        let store = makeStore([
            CalendarEvent(day: today, startMinute: 900, title: "午後"),
            CalendarEvent(day: today, startMinute: 0, title: "終日", isAllDay: true),
            CalendarEvent(day: today, startMinute: 540, title: "朝"),
            CalendarEvent(day: today.adding(days: 1), startMinute: 600, title: "翌日"),
        ])
        XCTAssertEqual(store.events(on: today).map(\.title), ["終日", "朝", "午後"])
        XCTAssertEqual(store.popoverRows(on: today).map(\.timeText), ["終日", "9:00", "15:00"])
    }

    func testPopoverRowsPrimaryAndSecondary() {
        let titled = CalendarEvent(day: today, startMinute: 600, title: "病院", locationName: "見本クリニック")
        let untitled = CalendarEvent(day: today, startMinute: 660, title: "", locationName: "広島駅", source: .appleCalendar)
        let bare = CalendarEvent(day: today, startMinute: 720, title: "", source: .appleCalendar)
        var info = TimyCueEventMetadata()
        info.color = .mint
        let store = makeStore([titled, untitled, bare], metadata: [titled.id: info])

        let rows = store.popoverRows(on: today)
        XCTAssertEqual(rows[0].primary, "病院", "予定名が主表示（仕様 §22）")
        XCTAssertEqual(rows[0].secondary, "見本クリニック", "場所は補助表示")
        XCTAssertEqual(rows[0].color, .mint)
        XCTAssertEqual(rows[1].primary, "広島駅", "予定名がなければ場所を主表示")
        XCTAssertNil(rows[1].secondary)
        XCTAssertEqual(rows[2].primary, "予定", "どちらもなければ汎用の表示（Q3）")
    }

    func testCellSummaryUsesDisplayTitleAndColor() {
        let event = CalendarEvent(day: today, startMinute: 600, title: "", locationName: "広島駅")
        var info = TimyCueEventMetadata()
        info.color = .lavender
        let store = makeStore([event], metadata: [event.id: info])
        XCTAssertEqual(store.summary(on: today), .titles([EventMark(title: "広島駅", color: .lavender)]))
        XCTAssertEqual(store.summary(on: today.adding(days: 1)), .empty)
    }

    func testAtMostTwoPopoversAndThirdReplacesOldest() {
        let store = makeStore([])
        let d1 = today, d2 = today.adding(days: 1), d3 = today.adding(days: 2)
        store.tapDay(d1)
        XCTAssertEqual(store.openDays, [d1])
        store.tapDay(d2)
        XCTAssertEqual(store.openDays, [d1, d2], "2 つ目も開く（仕様 §23）")
        store.tapDay(d3)
        XCTAssertEqual(store.openDays, [d2, d3], "3 つ目は古い方を閉じて入れ替える")
        XCTAssertTrue(store.isOpen(d3))
        XCTAssertFalse(store.isOpen(d1))
    }

    func testTappingOpenDayClosesIt() {
        let store = makeStore([])
        store.tapDay(today)
        store.tapDay(today)
        XCTAssertTrue(store.openDays.isEmpty)
    }

    func testReloadPicksUpNewEvents() throws {
        let repository = InMemoryEventRepository()
        let store = CalendarStore(repository: repository,
                                  metadataRepository: InMemoryEventMetadataRepository(),
                                  today: today)
        XCTAssertTrue(store.events(on: today).isEmpty)
        try repository.insert([CalendarEvent(day: today, startMinute: 600, title: "追加")])
        store.reload()
        XCTAssertEqual(store.events(on: today).map(\.title), ["追加"])
    }
}
