import XCTest
@testable import TimyCue

/// 3 分割画面の下カレンダー（2026-10-13 ユーザー決定「3 分割画面のカレンダー」）
final class EditorCalendarAxisTests: XCTestCase {
    /// 月の行は日付の行の半分の高さで考える
    private let axis = EditorCalendarAxis(around: CalendarMonth(year: 2026, month: 10), monthRowRatio: 0.5)
    private let october = CalendarMonth(year: 2026, month: 10)
    private let november = CalendarMonth(year: 2026, month: 11)

    func testWeekCountAndDayCount() {
        XCTAssertEqual(EditorCalendarAxis.weekCount(of: october), 5, "2026 年 10 月は木曜始まりの 31 日：5 行")
        XCTAssertEqual(EditorCalendarAxis.weekCount(of: CalendarMonth(year: 2027, month: 2)), 4, "2027 年 2 月は月曜始まりの 28 日：4 行")
        XCTAssertEqual(EditorCalendarAxis.weekCount(of: CalendarMonth(year: 2026, month: 8)), 6, "2026 年 8 月は土曜始まりの 31 日：6 行")
        XCTAssertEqual(EditorCalendarAxis.dayCount(of: CalendarMonth(year: 2028, month: 2)), 29, "うるう年")
        XCTAssertEqual(EditorCalendarAxis.dayCount(of: CalendarMonth(year: 2100, month: 2)), 28)
    }

    func testMonthsAreSeparatedByAMonthRow() {
        let lines = axis.lines(of: october)
        XCTAssertEqual(lines.first?.line, .month(october), "月の初めに 1 行空けて月を出す")
        XCTAssertEqual(lines.first?.height, 0.5)
        XCTAssertEqual(lines.count, 1 + 5)
        XCTAssertEqual(axis.top(of: october), 0)
        XCTAssertEqual(axis.top(of: november), 5.5, "10 月の月の行（0.5）＋ 5 週")
        XCTAssertEqual(axis.top(of: CalendarMonth(year: 2026, month: 9)), -5.5, "9 月は火曜始まりの 30 日：5 週")
        XCTAssertEqual(axis.month(at: 5.4), october)
        XCTAssertEqual(axis.month(at: 5.5), november)
        XCTAssertEqual(axis.month(at: -0.1), CalendarMonth(year: 2026, month: 9))
    }

    func testWeekCrossingMonthsIsSplitIntoTwoRows() {
        // 10/26〜11/1 の週：10 月の最後の行と、11 月の最初の行に分ける
        let crossing = CalendarWeek(containing: CalendarDay(year: 2026, month: 10, day: 31))
        let octoberLast = axis.lines(of: october).last
        let novemberFirstWeek = axis.lines(of: november)[1]
        XCTAssertEqual(octoberLast?.line, .week(october, crossing))
        XCTAssertEqual(novemberFirstWeek.line, .week(november, crossing), "同じ週でも、月ごとの行に分ける")
    }

    func testDayAtPointSkipsMonthRowAndOtherMonths() {
        // 行の高さ 40、列の幅 50。いちばん上は 10 月の月の行（高さ 20）
        XCTAssertNil(axis.day(atX: 10, y: 5, offset: 0, rowHeight: 40, columnWidth: 50), "月の行は日付ではない")
        XCTAssertNil(axis.day(atX: 10, y: 25, offset: 0, rowHeight: 40, columnWidth: 50),
                     "1 行目の月曜は 9/28。ほかの月の日は出さないので選べない")
        XCTAssertEqual(axis.day(atX: 160, y: 25, offset: 0, rowHeight: 40, columnWidth: 50),
                       CalendarDay(year: 2026, month: 10, day: 1), "1 行目の木曜")
        XCTAssertEqual(axis.day(atX: 320, y: 65, offset: 0, rowHeight: 40, columnWidth: 50),
                       CalendarDay(year: 2026, month: 10, day: 11), "2 行目の日曜")
        XCTAssertNil(axis.day(atX: 10, y: -1, offset: 0, rowHeight: 40, columnWidth: 50))
    }

    func testVisibleLines() {
        let lines = axis.visibleLines(offset: 4.75, visibleRows: 6)
        XCTAssertEqual(lines.first?.line, .week(october, CalendarWeek(containing: CalendarDay(year: 2026, month: 10, day: 26))),
                       "一部だけ見えている行も含む")
        XCTAssertTrue(lines.contains { $0.line == .month(november) })
        XCTAssertTrue(lines.allSatisfy { $0.top < 4.75 + 6 && $0.top + $0.height > 4.75 })
    }

    func testHeaderAndBandTexts() {
        XCTAssertEqual(EditorCalendarAxis.headerText(for: october), "2026年　10月", "いちばん上に年月を固定して出す")
        XCTAssertEqual(EditorCalendarAxis.bandText(for: november), "11月", "月の境目の月帯")
        XCTAssertEqual(EditorCalendarAxis.bandText(for: CalendarMonth(year: 2027, month: 1)), "2027年 1月", "1 月の月帯だけは年も出す")
    }

    func testHeaderSwitchesWhenTheMonthBandReachesTheTop() {
        let top = axis.top(of: november)
        XCTAssertEqual(axis.topMonth(at: top - 0.01), october, "11 月の月帯がまだ下にある間は 10 月")
        XCTAssertEqual(axis.topMonth(at: top), november, "11 月の月帯がいちばん上に重なったら 11 月へ")
        XCTAssertEqual(axis.topMonth(at: top + 0.3), november)
    }

    func testYearChangesWhenJanuaryReachesTheTop() {
        let january = CalendarMonth(year: 2027, month: 1)
        let top = axis.top(of: january)
        XCTAssertEqual(axis.topMonth(at: top).year, 2027, "1 月の月帯が上に重なったら年が変わる（ハプティクスの合図）")
        XCTAssertEqual(axis.topMonth(at: top - 0.1).year, 2026, "上へ戻して 1 月の月帯が下へ抜けたら前の年へ")
        XCTAssertEqual(axis.topMonth(at: axis.top(of: CalendarMonth(year: 2025, month: 12))).year, 2025, "前の年へもたどれる")
    }

    func testDraggingTheScrollBarMovesWithTheFinger() {
        XCTAssertEqual(EditorCalendarAxis.offset(afterDragging: -80, from: 2, rowHeight: 40), 4,
                       "上へなぞると、先の日付が下から出てくる。指と同じだけ動く")
        XCTAssertEqual(EditorCalendarAxis.offset(afterDragging: 40, from: 2, rowHeight: 40), 1)
        XCTAssertEqual(EditorCalendarAxis.offset(afterDragging: 40, from: 2, rowHeight: 0), 2)
    }

    func testInertiaSlowsDownLikeNormalScrolling() {
        let speed = EditorCalendarAxis.velocity(fromDragVelocity: -400, rowHeight: 40)
        XCTAssertEqual(speed, 10, "上へ速くなぞって離すと、先の方へ滑る（行／秒）")
        let step = EditorCalendarAxis.inertiaStep(velocity: speed, seconds: 0.1)
        XCTAssertLessThan(step.velocity, speed, "だんだん遅くなる")
        XCTAssertGreaterThan(step.moved, 0)
        XCTAssertEqual(EditorCalendarAxis.inertiaDistance(velocity: speed), speed * 0.4995, accuracy: 0.01,
                       "iPhone のふつうのスクロールと同じ減り方（0.998）")
        // 1 こまずつ足しても、滑りきる量に近づく
        var total = 0.0
        var v = speed
        for _ in 0..<600 {
            let s = EditorCalendarAxis.inertiaStep(velocity: v, seconds: 0.016)
            total += s.moved
            v = s.velocity
        }
        XCTAssertEqual(total, EditorCalendarAxis.inertiaDistance(velocity: speed), accuracy: 0.05)
    }

    func testRowsDoNotSquashWhenTheKeyboardShrinksTheCalendar() {
        XCTAssertEqual(EditorCalendarAxis.rowHeight(gridHeight: 300, visibleWeeks: 6, minimum: 38), 50,
                       "ふだんは日付の行 6 行ぶん")
        XCTAssertEqual(EditorCalendarAxis.rowHeight(gridHeight: 90, visibleWeeks: 6, minimum: 38), 38,
                       "キーボードで縮んだときは行をつぶさず、見える週を減らす（§67）")
    }

    // MARK: - 前後数年・遠くまで動かしてもずれない（2026-10-13 ユーザー決定の形を守る）

    func testMonthTopsStayConsistentForYearsInBothDirections() {
        // 前後 5 年：月の上端の差が、その月の高さ（月帯＋週の行）とちょうど合う。年の境目（12 月→1 月）も含む
        for k in -60...60 {
            let month = october.adding(months: k)
            let next = month.adding(months: 1)
            XCTAssertEqual(axis.top(of: next) - axis.top(of: month), axis.height(of: month),
                           "\(month.year)年\(month.month)月の上端と次の月の上端が合う")
            XCTAssertEqual(axis.month(at: axis.top(of: month)), month, "月の上端の位置はその月")
            XCTAssertEqual(axis.month(at: axis.top(of: next) - 0.01), month, "次の月の上端のすぐ上はまだその月")
        }
    }

    func testYearBoundaryBothWays() {
        let december = CalendarMonth(year: 2026, month: 12)
        let january = CalendarMonth(year: 2027, month: 1)
        XCTAssertEqual(axis.top(of: january) - axis.top(of: december), axis.height(of: december), "下へ年をまたぐ")
        let lastYearDecember = CalendarMonth(year: 2025, month: 12)
        let thisYearJanuary = CalendarMonth(year: 2026, month: 1)
        XCTAssertEqual(axis.top(of: thisYearJanuary) - axis.top(of: lastYearDecember), axis.height(of: lastYearDecember),
                       "基準の月より前（上へ）でも年をまたいでずれない")
        XCTAssertEqual(axis.topMonth(at: axis.top(of: thisYearJanuary) - 0.01).year, 2025)
    }

    func testFarScrollDoesNotDrift() {
        // 30 年先・30 年前でも、月の上端・中身がずれない（曜日を足し算でたどっても、暦で数えたのと同じ）
        for month in [october.adding(months: 360), october.adding(months: -360)] {
            let next = month.adding(months: 1)
            XCTAssertEqual(axis.top(of: next) - axis.top(of: month), axis.height(of: month))
            XCTAssertEqual(axis.month(at: axis.top(of: month) + 0.25), month, "月帯の中の位置はその月")
            let lines = axis.lines(of: month)
            XCTAssertEqual(lines.first?.line, .month(month))
            let firstWeek = lines.dropFirst().first
            XCTAssertEqual(firstWeek?.line, .week(month, CalendarWeek(containing: month.firstDay)),
                           "最初の週の行は、その月の 1 日を含む週")
        }
    }

    func testEveryDayOfTheMonthAppearsOnce() {
        // 前後 2 年：月の週の行に、その月の日が 1 回ずつだけ並ぶ（ほかの月の日は出さない）
        for k in -24...24 {
            let month = october.adding(months: k)
            let days = axis.lines(of: month).flatMap { placed -> [CalendarDay] in
                guard case .week(let lineMonth, let week) = placed.line else { return [] }
                return week.days.filter { CalendarMonth($0) == lineMonth }
            }
            XCTAssertEqual(days.count, EditorCalendarAxis.dayCount(of: month))
            XCTAssertEqual(Set(days).count, days.count)
            XCTAssertEqual(days.first, month.firstDay)
        }
    }

    // MARK: - 左右のスクロールバー

    @MainActor
    func testScrollBarFollowsTheFingerAndEndsDragging() {
        let scroller = EditorCalendarScroller()
        scroller.drag(translation: 0, rowHeight: 40, axis: axis)
        XCTAssertTrue(scroller.isDragging, "なぞっている間")
        scroller.drag(translation: -80, rowHeight: 40, axis: axis)
        XCTAssertEqual(scroller.offset, 2, "指と同じだけ動く（上へ 2 行ぶん → 先へ 2 行）")
        scroller.drag(translation: -20, rowHeight: 40, axis: axis)
        XCTAssertEqual(scroller.offset, 0.5, "なぞり始めの位置からの移動で決まる")

        scroller.endDrag(velocity: 0, rowHeight: 40, axis: axis)
        XCTAssertFalse(scroller.isDragging, "指を離したら、なぞっている状態は外れる")
        XCTAssertEqual(scroller.offset, 0.5, "止まった指で離したら、その位置のまま")

        scroller.drag(translation: 40, rowHeight: 40, axis: axis)
        XCTAssertEqual(scroller.offset, -0.5, "次になぞるときは、今の位置から動く")
        // 速く離したときも、なぞっている状態はすぐ外れる（滑る時間には頼らない）
        scroller.endDrag(velocity: -2000, rowHeight: 40, axis: axis)
        XCTAssertFalse(scroller.isDragging)
        scroller.stopInertia()
    }

    func testSafetyLimit() {
        XCTAssertEqual(axis.clamp(1_000_000), EditorCalendarAxis.maxOffset)
        XCTAssertEqual(axis.clamp(-1_000_000), -EditorCalendarAxis.maxOffset)
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
        XCTAssertEqual(store.valueText(for: .arrivalTarget), "0分前（予定開始時刻）", "新しい予定は全体既定値の初期値（Q70）")
        XCTAssertEqual(store.valueText(for: .transport), "自動")
        XCTAssertEqual(store.valueText(for: .notifications), "開始30分前・開始10分前・予定開始",
                       "場所なしの新しい予定は、通知の初期値も開始の基準（2026-10-14 決定）")

        store.content.title = "A社"
        store.content.metadata.arrivalTargetMinutes = 10
        XCTAssertEqual(store.valueText(for: .title), "A社")
        XCTAssertEqual(store.valueText(for: .arrivalTarget), "10分前", "§44 の例のとおり")
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
