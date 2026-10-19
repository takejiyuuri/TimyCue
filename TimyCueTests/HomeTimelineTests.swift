import XCTest
@testable import TimyCue

/// H2 の新しい Home の中身（spec §88.2〜§88.4・Q81〜Q84・Q87・Q89〜Q91・Q94・§13）。画面から切り離した計算
/// （HomeTimeline・HomeScreenModel・HomeCharacterMode）を、見本ではない実際の予定の形で確かめる
final class HomeTimelineTests: XCTestCase {
    private let calendar = Calendar.timyCue
    private let day = CalendarDay(year: 2026, month: 10, day: 19)
    private var tomorrow: CalendarDay { day.adding(days: 1) }

    private func at(_ minute: Int, on other: CalendarDay? = nil) -> Date {
        (other ?? day).date(atMinute: minute, calendar: calendar)
    }

    private func event(_ title: String, _ minute: Int, on other: CalendarDay? = nil, place: String? = nil,
                       duration: Int? = nil, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(day: other ?? day, startMinute: minute, durationMinutes: duration, title: title,
                      locationName: place, isAllDay: allDay)
    }

    /// 出発時刻の見込み：場所ありの予定は開始の 15 分前（DepartureStore の代わり）
    private func departures(_ travel: Int = 15) -> (CalendarEvent) -> DepartureEstimate {
        let calendar = self.calendar
        return { event in
            guard HomeSchedule.hasPlace(event), !event.isAllDay else { return .notNeeded }
            return .available(HomeSchedule.startDate(of: event, calendar: calendar).addingTimeInterval(TimeInterval(-travel * 60)))
        }
    }

    private func model(_ events: [CalendarEvent], _ minute: Int, on other: CalendarDay? = nil,
                       displayOnly: [CalendarEvent] = [],
                       estimate: ((CalendarEvent) -> DepartureEstimate)? = nil) -> HomeScreenModel {
        let resolved = estimate ?? departures()
        return HomeScreenModel.make(events: events, displayOnlyEvents: displayOnly, now: at(minute, on: other),
                                    calendar: calendar, estimate: resolved)
    }

    private func hm(_ date: Date) -> String {
        TimeText.hourMinute(Clock.minuteOfDay(date, calendar: calendar))
    }

    /// 「いま」より下の行を、確かめやすい文字にする（* は主状態の予定）
    private func describe(_ timeline: HomeTimeline) -> [String] {
        timeline.items.map { item -> String in
            let title = item.event?.displayTitle ?? ""
            let mark = item.isMain ? "*" : ""
            switch item.kind {
            case .departure:
                return "出発 \(hm(item.date)) \(title)\(mark)"
            case .start:
                return "開始 \(hm(item.date)) \(title)\(mark)"
            case .inProgress(let end):
                return "進行中 \(title)\(mark)" + (end.map { " 〜\(hm($0))" } ?? "")
            case .daySeparator(let separator):
                return "区切り \(separator.month)/\(separator.day)"
            case .message(let text):
                return "文 \(text)"
            }
        }
    }

    // MARK: - 出発の点と予定開始の点（Q81）

    func testDepartureAndStartAreSeparatePoints() {
        let visit = event("A社", 10 * 60 + 15, place: "広島駅")
        let online = event("オンライン", 11 * 60)
        let home = model([visit, online], 9 * 60)
        XCTAssertEqual(describe(home.timeline), ["出発 10:00 A社*", "開始 10:15 A社*", "開始 11:00 オンライン"],
                       "場所ありは出発と開始を別の点に、場所なしは開始の点だけ")
        XCTAssertEqual(home.timeline.eventCount, 2, "出発の点は予定の数に入れない")
    }

    func testNoDeparturePointWithoutARecommendedDeparture() {
        let visit = event("A社", 10 * 60 + 15, place: "広島駅")
        for estimate in [DepartureEstimate.pending, .unavailable(.placeUnconfirmed), .unavailable(.failed), .notNeeded] {
            let home = model([visit], 9 * 60, estimate: { _ in estimate })
            XCTAssertEqual(describe(home.timeline), ["開始 10:15 A社*"], "出発の点は推奨出発時刻があるときだけ（\(estimate)）")
        }
    }

    func testPointsKeepTheTimeOrderAcrossEvents() {
        let review = event("レビュー", 10 * 60)
        let visit = event("A社", 10 * 60 + 10, place: "広島駅")
        let home = model([visit, review], 9 * 60)
        XCTAssertEqual(describe(home.timeline), ["出発 9:55 A社", "開始 10:00 レビュー*", "開始 10:10 A社"],
                       "出発と予定開始の間にほかの予定があっても、時刻の順を崩さない（§88.2）")
    }

    // MARK: - 過ぎた出発の点と「いま」の並び（Q83・Q87）

    func testPastDepartureStaysBetweenTheFigureAndNowWhileGuided() {
        let visit = event("A社", 10 * 60 + 15, place: "広島駅", duration: 60)
        let before = model([visit], 9 * 60 + 59)
        XCTAssertNil(before.timeline.pastDeparture)
        XCTAssertEqual(before.timeline.aboveNow, [.figure, .now], "ふだんは 人型 → いま")

        for minute in [10 * 60, 10 * 60 + 3, 10 * 60 + 14] {
            let home = model([visit], minute)
            XCTAssertEqual(home.timeline.pastDeparture, HomeTimeline.PastDeparture(event: visit, leaveAt: at(10 * 60)),
                           "出発の案内が続いている間は、出発の点を「いま」の上に残す（\(hm(at(minute)))）")
            XCTAssertEqual(home.timeline.aboveNow, [.figure, .pastDeparture, .now], "人型 → 過ぎた出発の点 → いま")
            XCTAssertEqual(describe(home.timeline), ["開始 10:15 A社*"], "過ぎた出発の点は「いま」の下には出さない")
        }
        XCTAssertEqual(model([visit], 10 * 60).headline, "出発してください")
        XCTAssertEqual(model([visit], 10 * 60 + 3).headline, "出発時刻を3分過ぎています")

        let started = model([visit], 10 * 60 + 15)
        XCTAssertNil(started.timeline.pastDeparture, "「予定時刻になりました」に替わったら、通常の過去の表示に戻す")
        XCTAssertEqual(started.timeline.aboveNow, [.figure, .now])
        XCTAssertEqual(describe(started.timeline), ["進行中 A社* 〜11:15"])
        XCTAssertEqual(describe(model([visit], 10 * 60 + 18).timeline), ["進行中 A社 〜11:15"],
                       "開始の知らせが終わっても、終わりの時刻までは進行中（終わった予定にしない）")
    }

    func testOnlyTheGuidedEventKeepsItsPastDeparture() {
        let review = event("レビュー", 10 * 60 + 20)
        let visit = event("A社", 10 * 60 + 30, place: "広島駅")
        let home = model([visit, review], 10 * 60 + 16)
        XCTAssertNil(home.timeline.pastDeparture, "今案内している予定でなければ、過ぎた出発の点は残さない（最大 1 件）")
        XCTAssertEqual(describe(home.timeline), ["開始 10:20 レビュー*", "開始 10:30 A社"])
    }

    // MARK: - 終わった予定・進行中（Q83・Q84・Q91）

    func testFinishedEventsFoldAndInProgressEventsStayBelowNow() {
        let morning = event("朝会", 9 * 60, duration: 15)
        let review = event("レビュー", 10 * 60, duration: 60)
        let lunch = event("昼食", 12 * 60)
        let work = event("作業", 13 * 60 + 30, duration: 60)
        let visit = event("A社", 15 * 60, place: "広島駅")
        let home = model([visit, work, lunch, review, morning], 14 * 60 + 20)
        XCTAssertEqual(home.timeline.finishedEvents.map(\.title), ["朝会", "レビュー", "昼食"])
        XCTAssertEqual(home.timeline.finishedText, "終わった予定 3件")
        XCTAssertEqual(describe(home.timeline), ["進行中 作業 〜14:30", "出発 14:45 A社*", "開始 15:00 A社*"],
                       "進行中の予定は「いま」のすぐ下に終わりの時刻つきで")
        XCTAssertNil(model([visit], 9 * 60).timeline.finishedText, "終わった予定がなければ出さない")
    }

    func testAnEventWithoutAnEndStaysBelowNowOnlyDuringTheStartedNotice() {
        let call = event("電話", 10 * 60)
        let starting = model([call], 10 * 60 + 1)
        XCTAssertEqual(starting.headline, "予定時刻になりました")
        XCTAssertEqual(describe(starting.timeline), ["進行中 電話*"])
        XCTAssertTrue(starting.timeline.finishedEvents.isEmpty)
        let after = model([call], 10 * 60 + 3)
        XCTAssertEqual(after.timeline.finishedEvents.map(\.title), ["電話"], "約 3 分の知らせのあとは終わった予定へ")
        XCTAssertEqual(describe(after.timeline), ["文 予定はありません"])
    }

    // MARK: - 明日の予定・予定がないとき（§88.2・§13）

    func testTomorrowsFirstEventAppearsAfterTodaysEventsAreDone() {
        let morning = event("朝会", 9 * 60, duration: 15)
        let visit = event("A社", 9 * 60 + 30, on: tomorrow, place: "広島駅")
        let later = event("会議", 13 * 60, on: tomorrow)
        let home = model([morning, visit, later], 20 * 60)
        XCTAssertEqual(describe(home.timeline), ["区切り 10/20", "出発 9:15 A社*", "開始 9:30 A社*"],
                       "「明日」の区切りと明日の最初の予定 1 件")
        XCTAssertEqual(HomeTimeline.separatorText(tomorrow, today: day, calendar: calendar), "明日　10/20（火）")
        XCTAssertEqual(home.mode, .turtle)
    }

    func testTomorrowsDepartureTonightAlsoAppearsToday() {
        let dinner = event("夕食", 19 * 60)
        let flight = event("早朝の便", 30, on: tomorrow, place: "広島空港")
        let tonight = at(23 * 60 + 30)
        let home = model([dinner, flight], 17 * 60, estimate: { $0.id == flight.id ? .available(tonight) : .notNeeded })
        XCTAssertEqual(describe(home.timeline), ["開始 19:00 夕食*", "出発 23:30 早朝の便", "区切り 10/20", "開始 0:30 早朝の便"],
                       "明日の予定の推奨出発時刻が今日の夜にあるときは、その出発の点を今日のタイムラインにも出す")
    }

    func testMessagesWhenThereAreNoTimedEvents() {
        let empty = model([], 9 * 60)
        XCTAssertEqual(describe(empty.timeline), ["文 予定はありません"])
        XCTAssertEqual(empty.mode, .turtle, "予定がないときは亀（Q90）")
        XCTAssertNil(empty.clock)
        let holiday = event("休み", 0, allDay: true)
        XCTAssertEqual(describe(model([holiday], 9 * 60).timeline), ["文 今日は時間指定の予定はありません"], "§13")
        let visit = event("A社", 9 * 60 + 30, on: tomorrow, place: "広島駅")
        XCTAssertEqual(describe(model([holiday, visit], 9 * 60).timeline),
                       ["文 今日は時間指定の予定はありません", "区切り 10/20", "出発 9:15 A社*", "開始 9:30 A社*"])
    }

    func testAllDayAndDisplayOnlyEventsStayUnderTheDate() {
        let allDay = event("見本の終日予定", 0, allDay: true)
        let holiday = CalendarEvent(day: day, startMinute: 0, title: "祝日（見本）", isAllDay: true, source: .appleCalendar,
                                    calendarID: "holidays")
        let visit = event("A社", 10 * 60 + 15, place: "広島駅")
        let home = model([allDay, visit], 9 * 60, displayOnly: [holiday])
        XCTAssertEqual(home.timeline.allDayEvents.map(\.title), ["祝日（見本）", "見本の終日予定"],
                       "終日の予定と表示のみのカレンダーの予定は、日付の下に")
        XCTAssertEqual(home.timeline.allDayText, "終日　祝日（見本）・見本の終日予定")
        XCTAssertEqual(describe(home.timeline), ["出発 10:00 A社*", "開始 10:15 A社*"], "時間軸に混ぜない")
        let rest = event("休み", 0, allDay: true)
        XCTAssertEqual(model([allDay, rest, visit], 9 * 60, displayOnly: [holiday]).timeline.allDayText,
                       "終日　休み・祝日（見本） ほか1件", "多ければ「ほか○件」")
        XCTAssertNil(model([visit], 9 * 60).timeline.allDayText)
    }

    // MARK: - 更新のきっかけ（日付の変化・予定の追加と編集・連携 OFF）

    func testTheDayChangeMovesHomeToTheNewDay() {
        let late = event("夜の作業", 22 * 60, duration: 60)
        let next = event("朝会", 9 * 60, on: tomorrow, duration: 15)
        let before = model([late, next], 23 * 60 + 59)
        XCTAssertEqual(before.dateTitle, "10月19日（月）")
        XCTAssertEqual(before.timeline.finishedEvents.map(\.title), ["夜の作業"])
        let after = model([late, next], 1, on: tomorrow)
        XCTAssertEqual(after.dateTitle, "10月20日（火）", "日付が変わったら新しい日の Home")
        XCTAssertEqual(after.timeline.today, tomorrow)
        XCTAssertTrue(after.timeline.finishedEvents.isEmpty, "前の日の終わった予定は数えない")
        XCTAssertEqual(describe(after.timeline), ["開始 9:00 朝会*"], "「明日」の区切りは出さず、今日の予定として並べる")
    }

    func testAddingEditingAndRemovingEventsUpdatesTheTimeline() {
        var visit = event("A社", 10 * 60 + 15, place: "広島駅")
        let call = event("電話", 11 * 60)
        XCTAssertEqual(describe(model([visit], 9 * 60).timeline), ["出発 10:00 A社*", "開始 10:15 A社*"])
        XCTAssertEqual(describe(model([visit, call], 9 * 60).timeline), ["出発 10:00 A社*", "開始 10:15 A社*", "開始 11:00 電話"],
                       "予定を足した")
        visit.startMinute = 12 * 60
        XCTAssertEqual(describe(model([visit, call], 9 * 60).timeline), ["開始 11:00 電話*", "出発 11:45 A社", "開始 12:00 A社"],
                       "時刻を直したら並びと主状態の予定も変わる")
        visit.locationName = nil
        XCTAssertEqual(describe(model([visit, call], 9 * 60).timeline), ["開始 11:00 電話*", "開始 12:00 A社"],
                       "場所を消したら出発の点も消える")
        XCTAssertEqual(describe(model([call], 9 * 60).timeline), ["開始 11:00 電話*"], "予定を消した")
    }

    @MainActor
    private func eventTitles(_ store: CalendarStore) -> [String] {
        HomeScreenModel.make(events: store.guidanceEvents, now: at(9 * 60), calendar: calendar, estimate: departures())
            .timeline.items.compactMap { $0.isEventRow ? $0.event?.title : nil }
    }

    @MainActor
    func testTurningTheAppleLinkOffLeavesOnlyTimyCueEventsOnHome() {
        let local = InMemoryEventRepository(events: [event("TimyCueのみの予定", 13 * 60)])
        let apple = InMemoryEventRepository(events: [
            CalendarEvent(day: day, startMinute: 10 * 60 + 15, title: "Appleの予定", locationName: "広島駅",
                          source: .appleCalendar, calendarID: "work"),
        ])
        let switchable = SwitchableEventRepository(CombinedEventRepository(primary: apple, local: local))
        let store = CalendarStore(repository: switchable, metadataRepository: InMemoryEventMetadataRepository(), today: day)
        XCTAssertEqual(eventTitles(store), ["Appleの予定", "TimyCueのみの予定"], "Apple の予定と TimyCue のみの予定を両方")
        // 連携 OFF：保存先をこの iPhone の中だけにして読み直す（CalendarConnection が知らせ、CalendarStore が読み直す）
        switchable.use(local)
        store.reload()
        XCTAssertEqual(eventTitles(store), ["TimyCueのみの予定"], "連携 OFF の Home には TimyCue のみの予定だけ")
        switchable.use(CombinedEventRepository(primary: apple, local: local))
        store.reload()
        XCTAssertEqual(eventTitles(store), ["Appleの予定", "TimyCueのみの予定"], "ON に戻すと Apple の予定も出る")
    }

    // MARK: - 時計（Q94。今の時計の計算をそのまま使う）

    func testTheClockStartsExactly60MinutesBeforeAndEndsAtTheTarget() {
        let visit = event("A社", 10 * 60 + 15, place: "広島駅")
        XCTAssertNil(model([visit], 8 * 60 + 59).clock, "61 分前は時計を出さない")
        let first = model([visit], 9 * 60)
        XCTAssertEqual(first.clock?.face.remainingMinutes, 60, "ちょうど 60 分前から")
        XCTAssertEqual(first.clock?.word, "出発")
        XCTAssertEqual(first.clock?.target, HomeSchedule.ClockTarget(date: at(10 * 60), isDeparture: true), "場所ありは出発時刻が終点")
        XCTAssertEqual(model([visit], 9 * 60 + 59).clock?.face.remainingMinutes, 1)
        let atDeparture = model([visit], 10 * 60)
        XCTAssertNil(atDeparture.clock, "出発時刻で時計を終える")
        XCTAssertEqual(atDeparture.headline, "出発してください")

        let online = event("オンライン", 10 * 60)
        XCTAssertNil(model([online], 8 * 60 + 59).clock)
        let placeless = model([online], 9 * 60)
        XCTAssertEqual(placeless.clock?.face.remainingMinutes, 60)
        XCTAssertEqual(placeless.clock?.word, "開始", "場所なしは「開始まで」")
        XCTAssertEqual(placeless.clock?.target, HomeSchedule.ClockTarget(date: at(10 * 60), isDeparture: false), "場所なしは開始時刻が終点")
        XCTAssertNil(model([online], 10 * 60).clock)
        XCTAssertEqual(model([online], 10 * 60).headline, "予定時刻になりました")
    }

    func testTheClockUsesTheSameFaceAsBefore() {
        // H2 の Home は、1.0 (31) で実時間の動きを確かめた時計の計算（HomeClockMath.face）をそのまま使う
        let visit = event("A社", 10 * 60 + 15, place: "広島駅")
        let home = model([visit], 9 * 60 + 37)
        XCTAssertEqual(home.clock?.face, HomeClockMath.face(now: at(9 * 60 + 37), target: at(10 * 60), calendar: calendar))
        XCTAssertEqual(HomeClockMath.remainingMinutes(now: at(9 * 60 + 37).addingTimeInterval(40), target: at(10 * 60), calendar: calendar), 23,
                       "秒では分を変えない")
    }

    // MARK: - キャラクターの 3 モード（Q89・Q90）

    func testCharacterModeFollowsTheRemainingTime() {
        XCTAssertEqual(HomeCharacterMode.mode(remainingMinutes: 61), .turtle, "残り 60 分より前は亀")
        XCTAssertEqual(HomeCharacterMode.mode(remainingMinutes: 60), .human, "60〜31 分は人型")
        XCTAssertEqual(HomeCharacterMode.mode(remainingMinutes: 31), .human)
        XCTAssertEqual(HomeCharacterMode.mode(remainingMinutes: 30), .rabbit, "30 分以下はうさぎ")
        XCTAssertEqual(HomeCharacterMode.mode(remainingMinutes: 1), .rabbit)
        XCTAssertEqual(HomeCharacterMode.mode(remainingMinutes: 0), .rabbit)

        let visit = event("A社", 10 * 60 + 15, place: "広島駅")
        let table: [(minute: Int, mode: CharacterMode)] = [
            (8 * 60 + 59, .turtle), (9 * 60, .human), (9 * 60 + 29, .human), (9 * 60 + 30, .rabbit),
            (9 * 60 + 59, .rabbit), (10 * 60, .rabbit), (10 * 60 + 5, .rabbit),
        ]
        for row in table {
            XCTAssertEqual(model([visit], row.minute).mode, row.mode, "\(hm(at(row.minute)))（場所ありは出発まで。出発を過ぎて案内中はうさぎ）")
        }
        let online = event("オンライン", 10 * 60)
        XCTAssertEqual(model([online], 8 * 60 + 59).mode, .turtle, "場所なしは開始までの残りで")
        XCTAssertEqual(model([online], 9 * 60 + 29).mode, .human)
        XCTAssertEqual(model([online], 9 * 60 + 30).mode, .rabbit)
        XCTAssertEqual(model([visit], 9 * 60 + 14, estimate: { _ in .pending }).mode, .turtle, "出発時刻をまだ出せないときは開始まで")
        XCTAssertEqual(model([visit], 9 * 60 + 15, estimate: { _ in .pending }).mode, .human)
    }

    func testTheDateTitle() {
        XCTAssertEqual(HomeTimeline.dateTitle(day, calendar: calendar), "10月19日（月）")
    }
}
