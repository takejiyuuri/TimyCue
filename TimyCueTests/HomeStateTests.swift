import XCTest
@testable import TimyCue

/// ホームの主状態（追加仕様書 §45。2026-10-14 指示「Home の状態遷移」）
final class HomeStateTests: XCTestCase {
    private let calendar = Calendar.timyCue
    private let day = CalendarDay(year: 2026, month: 10, day: 14)

    private func at(_ minute: Int) -> Date {
        day.date(atMinute: minute, calendar: calendar)
    }

    private func event(_ title: String, at minute: Int, place: String? = nil) -> CalendarEvent {
        var event = CalendarEvent(day: day, startMinute: minute, title: title)
        event.locationName = place
        return event
    }

    private func state(_ events: [CalendarEvent], _ now: Int,
                       estimate: (CalendarEvent) -> DepartureEstimate = DepartureEstimate.development(for:)) -> HomeState {
        HomeState.resolve(events: events, now: at(now), calendar: calendar, estimate: estimate)
    }

    // MARK: - 予定なし

    func testNoEvents() {
        XCTAssertEqual(state([], 9 * 60), .noEvents(onlyAllDayToday: false))
        let allDay = CalendarEvent(day: day, startMinute: 0, title: "休み", isAllDay: true)
        XCTAssertEqual(state([allDay], 9 * 60), .noEvents(onlyAllDayToday: true), "今日は終日の予定だけ")
    }

    // MARK: - 場所なしの予定：開始のカウントダウン（追加仕様書 §36.2・§44.11）

    func testEventWithoutPlaceCountsDownToTheStart() {
        let meeting = event("打合せ", at: 17 * 60 + 15)
        XCTAssertEqual(state([meeting], 16 * 60 + 14), .upcoming(meeting), "開始の 60 分より前は静かな表示（時計は出さない）")
        XCTAssertEqual(state([meeting], 16 * 60 + 15), .startCountdown(meeting), "開始の 60 分前から時計")
        XCTAssertEqual(state([meeting], 16 * 60 + 52).clockTarget(calendar: calendar),
                       HomeSchedule.ClockTarget(date: at(17 * 60 + 15), isDeparture: false), "「開始まで」「開始予定」")
        XCTAssertEqual(state([meeting], 17 * 60 + 14), .startCountdown(meeting))
        XCTAssertEqual(state([meeting], 17 * 60 + 15), .eventStarted(meeting), "0 分で時計を終え「予定時刻になりました」")
        XCTAssertEqual(state([meeting], 17 * 60 + 15).headline, "予定時刻になりました")
        XCTAssertEqual(state([meeting], 17 * 60 + 17), .eventStarted(meeting), "約 3 分")
        XCTAssertEqual(state([meeting], 17 * 60 + 18), .noEvents(onlyAllDayToday: false), "そのあとは次に行動が必要な予定を選び直す")
    }

    func testEventWithoutPlaceNeverUsesDeparture() {
        let meeting = event("打合せ", at: 17 * 60 + 15, place: "  ")
        XCTAssertEqual(DepartureEstimate.development(for: meeting), .notNeeded, "空白だけの場所は場所なし")
        XCTAssertEqual(state([meeting], 16 * 60 + 52), .startCountdown(meeting))
    }

    func testAfterTheStartedNoticeTheNextEventIsChosen() {
        let first = event("朝会", at: 9 * 60)
        let second = event("打合せ", at: 9 * 60 + 40)
        XCTAssertEqual(state([first, second], 9 * 60 + 2), .eventStarted(first))
        XCTAssertEqual(state([first, second], 9 * 60 + 3), .startCountdown(second), "3 分たったら次の予定（40 分前なので時計）")
    }

    // MARK: - 場所ありの予定：開発中は開始で仮に動かす（追加仕様書 §44.11）

    func testEventWithPlaceUsesTheStartOnlyWhileDepartureIsNotImplemented() {
        let visit = event("A社", at: 17 * 60 + 15, place: "広島駅")
        XCTAssertEqual(DepartureEstimate.development(for: visit), .notImplemented)
        XCTAssertEqual(state([visit], 16 * 60 + 52), .startCountdown(visit), "開発中だけ「開始まで」")
    }

    // MARK: - 場所ありの予定：出発時刻が分かるとき

    func testDepartureCountdownThenDepartureTimeThenOverdue() {
        let visit = event("A社", at: 17 * 60 + 15, place: "広島駅")
        let leaveAt = at(16 * 60 + 40)
        let estimate: (CalendarEvent) -> DepartureEstimate = { _ in .available(leaveAt) }
        XCTAssertEqual(state([visit], 15 * 60 + 39, estimate: estimate), .upcoming(visit), "出発の 60 分より前は静かな表示")
        XCTAssertEqual(state([visit], 15 * 60 + 40, estimate: estimate), .departureCountdown(visit, departure: leaveAt), "出発の 60 分前から時計")
        XCTAssertEqual(state([visit], 16 * 60 + 17, estimate: estimate).clockTarget(calendar: calendar),
                       HomeSchedule.ClockTarget(date: leaveAt, isDeparture: true), "「出発まで」「出発予定」")
        XCTAssertEqual(state([visit], 16 * 60 + 40, estimate: estimate), .departureTime(visit, departure: leaveAt),
                       "出発時刻になったら時計を終え「出発してください」")
        XCTAssertEqual(state([visit], 16 * 60 + 40, estimate: estimate).headline, "出発してください")
        XCTAssertNil(state([visit], 16 * 60 + 40, estimate: estimate).clockTarget(calendar: calendar), "リングが 0 の時計を残さない")
        XCTAssertEqual(state([visit], 16 * 60 + 42, estimate: estimate), .departureTime(visit, departure: leaveAt))
        XCTAssertEqual(state([visit], 16 * 60 + 43, estimate: estimate), .departureOverdue(visit, departure: leaveAt, minutesLate: 3),
                       "3 分以上は「出発時刻を○分過ぎています」（spec Q46）")
        XCTAssertEqual(state([visit], 16 * 60 + 50, estimate: estimate).headline, "出発時刻を10分過ぎています")
        XCTAssertEqual(state([visit], 17 * 60 + 15, estimate: estimate), .eventStarted(visit), "予定開始時刻には「予定時刻になりました」")
    }

    func testNextDepartureComesBeforeTheStartedNotice() {
        let meeting = event("朝会", at: 10 * 60)
        let visit = event("A社", at: 10 * 60 + 30, place: "広島駅")
        let estimate: (CalendarEvent) -> DepartureEstimate = { $0 == visit ? .available(self.at(10 * 60 + 1)) : .notNeeded }
        XCTAssertEqual(state([meeting, visit], 10 * 60, estimate: estimate), .eventStarted(meeting))
        XCTAssertEqual(state([meeting, visit], 10 * 60 + 1, estimate: estimate), .departureTime(visit, departure: at(10 * 60 + 1)),
                       "次の予定の出発時刻になったら、「予定時刻になりました」の途中でも次の案内を優先（追加仕様書 §5.1・§5.4）")
    }

    // MARK: - 出発時刻を計算できないとき（追加仕様書 §44.11）

    func testUnavailableDepartureIsItsOwnStateNotTheStartCountdown() {
        let visit = event("A社", at: 17 * 60 + 15, place: "広島駅")
        let result = state([visit], 16 * 60 + 52, estimate: { _ in .unavailable })
        XCTAssertEqual(result, .departureUnavailable(visit), "製品では黙って開始のカウントダウンへ切り替えない")
        XCTAssertNil(result.clockTarget(calendar: calendar))
        XCTAssertEqual(result.event, visit)
    }
}
