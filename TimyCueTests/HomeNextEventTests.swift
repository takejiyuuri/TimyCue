import XCTest
@testable import TimyCue

/// Home の「次の予定」の選び方（2026-10-17 実機の不具合「次の予定に直近の予定が出ない」の回帰テスト）。
/// 次の予定を選ぶことと、アナログ時計を出し始めること（残り 60 分。spec §6）は別の処理：
/// 60 分より先でも次の予定は選び、時計だけを出さない
@MainActor
final class HomeNextEventTests: XCTestCase {
    private let calendar = Calendar.timyCue
    private let today = CalendarDay(year: 2026, month: 10, day: 17)
    private var tomorrow: CalendarDay { today.adding(days: 1) }
    private let now = 18 * 60 + 30
    private let evening = 19 * 60 + 35

    private func at(_ minute: Int, on day: CalendarDay? = nil) -> Date {
        (day ?? today).date(atMinute: minute, calendar: calendar)
    }

    private func event(_ title: String, _ day: CalendarDay, _ minute: Int, place: String? = nil) -> CalendarEvent {
        var event = CalendarEvent(day: day, startMinute: minute, title: title)
        event.locationName = place
        return event
    }

    private func state(_ events: [CalendarEvent], _ minute: Int,
                       estimate: (CalendarEvent) -> DepartureEstimate = DepartureEstimate.development(for:)) -> HomeState {
        HomeState.resolve(events: events, now: at(minute), calendar: calendar, estimate: estimate)
    }

    // MARK: - 1. 当日に場所なしの予定が 1 件

    func testTodaysEventWithoutPlaceIsTheNextEventEvenBeforeTheClock() {
        let meeting = event("見本：場所なし", today, evening)
        let home = state([meeting], now)
        XCTAssertEqual(home, .upcoming(meeting), "残り 65 分でも次の予定に出す")
        XCTAssertNil(home.clockTarget(calendar: calendar), "時計はまだ出さない（60 分より前）")
        XCTAssertNil(HomeClockMath.face(now: at(now), target: at(evening), calendar: calendar))
    }

    // MARK: - 2. 当日と翌日に予定がある

    func testTodayComesBeforeTomorrowWhateverTheOrder() {
        let tonight = event("今日の予定", today, evening)
        let tomorrowMorning = event("明日の予定", tomorrow, 10 * 60)
        XCTAssertEqual(state([tomorrowMorning, tonight], now), .upcoming(tonight))
        XCTAssertEqual(state([tonight, tomorrowMorning], now), .upcoming(tonight), "並び順に依らない")
        XCTAssertEqual(state([tomorrowMorning, tonight], evening + 2), .eventStarted(tonight), "開始から約 3 分は「予定時刻になりました」")
        XCTAssertEqual(state([tomorrowMorning, tonight], evening + 3), .upcoming(tomorrowMorning), "そのあとは明日の予定")
    }

    // MARK: - 3. 場所あり・場所なしが混ざる

    func testEventsWithAndWithoutPlaceAreMixed() {
        let withoutPlace = event("場所なし", today, evening)
        let withPlace = event("場所あり", today, 21 * 60, place: "見本の場所")
        let blankPlace = event("場所が空白", today, evening, place: "  ")
        let tomorrowWithPlace = event("明日の場所あり", tomorrow, 10 * 60, place: "見本の場所")
        let estimate: (CalendarEvent) -> DepartureEstimate = { event in
            event.id == withPlace.id ? .available(self.at(20 * 60 + 20)) : DepartureEstimate.development(for: event)
        }
        let events = [tomorrowWithPlace, withPlace, withoutPlace]
        XCTAssertEqual(state(events, now, estimate: estimate), .upcoming(withoutPlace), "場所の有無で候補から外さない")
        XCTAssertEqual(state(events, evening - 60, estimate: estimate), .startCountdown(withoutPlace))
        XCTAssertEqual(state(events, evening - 60, estimate: estimate).clockTarget(calendar: calendar)?.isDeparture, false,
                       "場所なしは開始まで")
        XCTAssertEqual(state(events, evening + 5, estimate: estimate),
                       .departureCountdown(withPlace, departure: at(20 * 60 + 20)), "知らせのあとは場所ありの予定の出発まで")
        XCTAssertEqual(state([tomorrowWithPlace, blankPlace], now), .upcoming(blankPlace), "場所が空白だけでも場所なしとして選ぶ")
    }

    // MARK: - 4. 予定を追加・変更・削除して Home へ戻る

    func testAddingChangingAndDeletingEventsUpdatesTheNextEvent() throws {
        let tomorrowMorning = event("明日の予定", tomorrow, 10 * 60)
        let repository = InMemoryEventRepository(events: [tomorrowMorning])
        let store = CalendarStore(repository: repository, metadataRepository: InMemoryEventMetadataRepository(), today: today)
        XCTAssertEqual(state(store.guidanceEvents, now), .upcoming(tomorrowMorning))

        // 追加（保存のあとの読み直しは画面と同じく reload）
        var added = event("今日の予定", store.dayForNewEvent, evening)
        try repository.insert([added])
        store.reload()
        XCTAssertEqual(state(store.guidanceEvents, now), .upcoming(added), "追加した今日の予定")

        // 変更：時刻を変える → 明後日へ動かす
        added.startMinute = 20 * 60
        try repository.update(added)
        store.reload()
        XCTAssertEqual(state(store.guidanceEvents, now), .upcoming(added))
        added.day = today.adding(days: 2)
        try repository.update(added)
        store.reload()
        XCTAssertEqual(state(store.guidanceEvents, now), .upcoming(tomorrowMorning), "明後日へ動かしたら明日の予定")

        // 削除
        try repository.delete(id: added.id)
        store.reload()
        XCTAssertEqual(state(store.guidanceEvents, now), .upcoming(tomorrowMorning))
    }

    /// 今回の不具合：カレンダーの「今日」が前の日のまま残ると、［＋］の初めの日が前の日になり、
    /// 今日のつもりの予定が前の日に入る（カレンダーでは「今日」に見える）。Home は本当の時刻で選ぶので、その予定は過去として外れる
    func testStaleCalendarTodayPutsTheNewEventOnThePreviousDay() throws {
        let tomorrowMorning = event("明日の予定", tomorrow, 10 * 60)
        let repository = InMemoryEventRepository(events: [tomorrowMorning])
        // 前の日から裏に残していたアプリ（カレンダーの「今日」は 10/16 のまま）
        let store = CalendarStore(repository: repository, metadataRepository: InMemoryEventMetadataRepository(),
                                  today: today.adding(days: -1))
        XCTAssertEqual(store.dayForNewEvent, today.adding(days: -1), "直す前の動き：［＋］は前の日から始まる")
        let wrong = event("今日のつもり", store.dayForNewEvent, evening)
        try repository.insert([wrong])
        store.reload()
        XCTAssertEqual(state(store.guidanceEvents, now), .upcoming(tomorrowMorning), "症状：Home は別の日の予定を出す")
        try repository.delete(id: wrong.id)

        // 直したあと：前面に戻したとき・日付が変わったときに「今日」を直す（RootTabView）
        store.updateToday(today)
        XCTAssertEqual(store.today, today)
        XCTAssertEqual(store.dayForNewEvent, today, "［＋］は本当の今日から始まる")
        let right = event("今日の予定", store.dayForNewEvent, evening)
        try repository.insert([right])
        store.reload()
        XCTAssertEqual(state(store.guidanceEvents, now), .upcoming(right), "Home の次の予定は今日 19:35")
    }

    // MARK: - 5. 予定が 60 分より先

    func testMoreThanSixtyMinutesAwayIsQuietButStillTheNextEvent() {
        let meeting = event("場所なし", today, evening)
        for minute in [now, evening - 61] {
            let home = state([meeting], minute)
            XCTAssertEqual(home, .upcoming(meeting), "\(TimeText.hourMinute(minute))：次の予定")
            XCTAssertNil(home.clockTarget(calendar: calendar), "\(TimeText.hourMinute(minute))：時計はまだ")
        }
    }

    // MARK: - 6. 予定が 60 分以内

    func testWithinSixtyMinutesTheClockStarts() throws {
        let meeting = event("場所なし", today, evening)
        XCTAssertEqual(state([meeting], evening - 60), .startCountdown(meeting), "ちょうど 60 分で時計を出し始める")
        let face = try XCTUnwrap(HomeClockMath.face(now: at(evening - 60), target: at(evening), calendar: calendar))
        XCTAssertEqual(face.remainingMinutes, 60)
        XCTAssertEqual(state([meeting], evening - 1), .startCountdown(meeting))
        XCTAssertEqual(state([meeting], evening), .eventStarted(meeting), "開始時刻で「予定時刻になりました」")
    }
}
