import XCTest
@testable import TimyCue

final class CalendarWeekTests: XCTestCase {
    func testWeekStartsOnMondayAndCrossesMonthBoundary() {
        // 2026 年 10 月 31 日は土曜
        let week = CalendarWeek(containing: CalendarDay(year: 2026, month: 10, day: 31))
        XCTAssertEqual(week.start, CalendarDay(year: 2026, month: 10, day: 26), "月曜始まり（仕様 §19）")
        XCTAssertEqual(week.days.map(\.day), [26, 27, 28, 29, 30, 31, 1], "月の境目も途切れず続ける（v1.1）")
    }

    func testMonthLabelOnlyOnWeekContainingFirstDay() {
        let boundary = CalendarWeek(containing: CalendarDay(year: 2026, month: 10, day: 26))
        XCTAssertEqual(boundary.monthStartingInWeek, CalendarMonth(year: 2026, month: 11), "11 月 1 日を含む週に「11月」（Q18）")
        XCTAssertNil(CalendarWeek(containing: CalendarDay(year: 2026, month: 10, day: 19)).monthStartingInWeek)
        XCTAssertEqual(CalendarMonth(year: 2026, month: 11).monthLabel, "11月", "月表示列は月だけ（Q20）")
    }

    func testStickyMonthSwitchesWhenNextMonthsFirstWeekIsOnTop() {
        let lateOctober = CalendarWeek(containing: CalendarDay(year: 2026, month: 10, day: 19))
        XCTAssertEqual(lateOctober.stickyMonth, CalendarMonth(year: 2026, month: 10))
        let boundary = lateOctober.adding(weeks: 1)
        XCTAssertEqual(boundary.stickyMonth, CalendarMonth(year: 2026, month: 11),
                       "11 月 1 日を含む週が一番上に来たら 10月 → 11月（Q19）")
    }

    func testYearSwitchesWhenJanuaryWeekIsOnTop() {
        let newYearWeek = CalendarWeek(containing: CalendarDay(year: 2026, month: 12, day: 31))
        XCTAssertEqual(newYearWeek.days.map(\.day), [28, 29, 30, 31, 1, 2, 3])
        XCTAssertEqual(newYearWeek.stickyMonth.yearLabel, "2027年", "次年 1 月の週が一番上で 2026年 → 2027年（Q20）")
        XCTAssertEqual(newYearWeek.adding(weeks: -1).stickyMonth.yearLabel, "2026年")
    }

    func testAddingMonthsAcrossYears() {
        XCTAssertEqual(CalendarMonth(year: 2026, month: 12).adding(months: 1), CalendarMonth(year: 2027, month: 1))
        XCTAssertEqual(CalendarMonth(year: 2026, month: 1).adding(months: -1), CalendarMonth(year: 2025, month: 12))
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

    func testWeeksStartAroundTodayWithCurrentMonthOnTop() {
        let store = makeStore([])
        XCTAssertEqual(store.weeks, store.weeks.sorted(), "週は縦に順につながる（仕様 §19）")
        XCTAssertEqual(store.weeks.count, CalendarStore.initialWeeksBefore + CalendarStore.initialWeeksAfter + 1)
        XCTAssertTrue(store.weeks.contains(CalendarWeek(containing: today)))
        XCTAssertEqual(store.topWeek, CalendarWeek(containing: CalendarDay(year: 2026, month: 10, day: 1)),
                       "最初は今月の 1 日を含む週を一番上に")
        XCTAssertEqual(store.stickyMonth.monthLabel, "10月")
        XCTAssertEqual(store.stickyMonth.yearLabel, "2026年")
    }

    func testStickyMonthFollowsTopWeek() {
        let store = makeStore([])
        store.topWeekID = CalendarDay(year: 2026, month: 10, day: 26)
        XCTAssertEqual(store.stickyMonth.monthLabel, "11月")
    }

    func testWeeksAreAddedTowardScrollDirection() {
        let store = makeStore([])
        let first = store.weeks.first!
        let last = store.weeks.last!
        let count = store.weeks.count

        store.weekDidAppear(last)
        XCTAssertEqual(store.weeks.count, count + CalendarStore.weeksPerExtension, "下の端に近づいたら先の週を足す（Q13）")
        XCTAssertEqual(store.weeks.last, last.adding(weeks: CalendarStore.weeksPerExtension))

        store.weekDidAppear(first)
        XCTAssertEqual(store.weeks.first, first.adding(weeks: -CalendarStore.weeksPerExtension), "上の端なら前の週を足す")
        XCTAssertEqual(store.weeks, store.weeks.sorted())

        store.weekDidAppear(store.weeks[store.weeks.count / 2])
        XCTAssertEqual(store.weeks.count, count + CalendarStore.weeksPerExtension * 2, "真ん中では足さない")
    }

    func testWeeksStopAtSafetyLimit() {
        let store = makeStore([])
        for _ in 0..<(CalendarStore.maxWeeksFromToday / CalendarStore.weeksPerExtension + 2) {
            store.extendAfter()
        }
        XCTAssertEqual(store.weeks.last, CalendarWeek(containing: today).adding(weeks: CalendarStore.maxWeeksFromToday),
                       "内部の安全上限で止まる")
    }

    func testEventsAreAllDayFirstThenByStartTime() {
        let store = makeStore([
            CalendarEvent(day: today, startMinute: 900, title: "午後"),
            CalendarEvent(day: today, startMinute: 0, title: "終日", isAllDay: true),
            CalendarEvent(day: today, startMinute: 540, title: "朝"),
            CalendarEvent(day: today.adding(days: 1), startMinute: 600, title: "翌日"),
        ])
        XCTAssertEqual(store.events(on: today).map(\.title), ["終日", "朝", "午後"], "終日 → 時間指定を開始時刻順（Q8）")
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
        XCTAssertTrue(store.openDays.isEmpty, "開いている日をもう一度押すと閉じる（Q9）")
    }

    func testTappingOutsideClosesPopovers() {
        let store = makeStore([])
        store.tapDay(today)
        store.tapDay(today.adding(days: 1))
        store.closeAllPopovers()
        XCTAssertTrue(store.openDays.isEmpty, "吹き出しの外を押すと閉じる（Q9）")
    }

    func testPopoverTimeShowsEndOnlyWhenSet() {
        let withEnd = CalendarEvent(day: today, startMinute: 600, durationMinutes: 90, title: "A")
        let withoutEnd = CalendarEvent(day: today, startMinute: 600, title: "B")
        XCTAssertEqual(CalendarStore.timeText(for: withEnd), "10:00–11:30", "終了時刻があれば出す（Q12）")
        XCTAssertEqual(CalendarStore.timeText(for: withoutEnd), "10:00", "終了未設定なら開始だけ")
    }

    func testEmptyDayStillOpensPopover() {
        let store = makeStore([])
        store.tapDay(today)
        XCTAssertTrue(store.isOpen(today), "予定のない日も「予定はありません」の吹き出しを出す（Q10）")
        XCTAssertTrue(store.popoverRows(on: today).isEmpty)
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
