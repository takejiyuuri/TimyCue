import XCTest
@testable import TimyCue

/// ホームに出す予定の決まり（v1.1「ホーム」・§13・2026-10-12「ホームの切り替え」）
final class HomeScheduleTests: XCTestCase {
    private let today = CalendarDay(year: 2026, month: 10, day: 12)

    private func at(_ day: CalendarDay, _ minute: Int) -> Date {
        day.date(atMinute: minute)
    }

    func testNextEventIsTheNearestUpcomingTimedEvent() {
        let morning = CalendarEvent(day: today, startMinute: 9 * 60, title: "朝会")
        let afternoon = CalendarEvent(day: today, startMinute: 14 * 60, title: "A社")
        let tomorrow = CalendarEvent(day: today.adding(days: 1), startMinute: 8 * 60, title: "現場")
        let allDay = CalendarEvent(day: today, startMinute: 0, title: "休み", isAllDay: true)
        let events = [tomorrow, afternoon, allDay, morning]

        XCTAssertEqual(HomeSchedule.nextEvent(in: events, now: at(today, 8 * 60))?.title, "朝会", "次の予定 1 件だけ")
        XCTAssertEqual(HomeSchedule.nextEvent(in: events, now: at(today, 10 * 60))?.title, "A社",
                       "前の予定が始まったら次の予定を主表示にし、前の予定を残さない")
        XCTAssertEqual(HomeSchedule.nextEvent(in: events, now: at(today, 15 * 60))?.title, "現場", "今日が終わったら明日の予定")
        XCTAssertNil(HomeSchedule.nextEvent(in: [allDay], now: at(today, 8 * 60)), "終日の予定は出発の対象にしない（§13）")
    }

    func testOnlyAllDayToday() {
        let allDay = CalendarEvent(day: today, startMinute: 0, title: "休み", isAllDay: true)
        let evening = CalendarEvent(day: today, startMinute: 19 * 60, title: "食事")
        XCTAssertTrue(HomeSchedule.hasOnlyAllDayToday(in: [allDay], now: at(today, 8 * 60)),
                      "「今日は時間指定の予定はありません」（§13）")
        XCTAssertFalse(HomeSchedule.hasOnlyAllDayToday(in: [allDay, evening], now: at(today, 8 * 60)))
        XCTAssertTrue(HomeSchedule.hasOnlyAllDayToday(in: [allDay, evening], now: at(today, 20 * 60)),
                      "時間指定の予定が終わったあとは、終日の予定だけ")
        XCTAssertFalse(HomeSchedule.hasOnlyAllDayToday(in: [], now: at(today, 8 * 60)))
    }

    func testCountdown() {
        let now = at(today, 9 * 60)
        XCTAssertEqual(HomeSchedule.countdownText(from: now, to: at(today, 9 * 60 + 45)), "開始まであと45分")
        XCTAssertEqual(HomeSchedule.countdownText(from: now, to: at(today, 11 * 60 + 5)), "開始まであと2時間5分")
        XCTAssertEqual(HomeSchedule.countdownText(from: now, to: at(today, 12 * 60)), "開始まであと3時間")
        XCTAssertEqual(HomeSchedule.countdownText(from: now, to: at(today.adding(days: 2), 9 * 60)), "",
                       "1 日以上先は日付と時刻だけ")
    }

    // MARK: - 追加仕様書 §5.1・§5.2

    func testStartedNoticeForAboutThreeMinutesThenNextEvent() {
        let meeting = CalendarEvent(day: today, startMinute: 10 * 60, title: "会議")
        let lunch = CalendarEvent(day: today, startMinute: 12 * 60, title: "昼食")
        let events = [meeting, lunch]
        XCTAssertEqual(HomeSchedule.main(in: events, now: at(today, 9 * 60 + 59)), .upcoming(meeting))
        XCTAssertEqual(HomeSchedule.main(in: events, now: at(today, 10 * 60)), .started(meeting),
                       "開始時刻には「予定時刻になりました」")
        XCTAssertEqual(HomeSchedule.main(in: events, now: at(today, 10 * 60 + 2)), .started(meeting), "最大 3 分出す")
        XCTAssertEqual(HomeSchedule.main(in: events, now: at(today, 10 * 60 + 3)), .upcoming(lunch),
                       "そのあとは主表示から外して次の予定へ")
        let allDay = CalendarEvent(day: today, startMinute: 0, title: "休み", isAllDay: true)
        XCTAssertNil(HomeSchedule.main(in: [allDay], now: at(today, 0)), "終日の予定は対象にしない")
    }

    func testNextDepartureTakesPriorityOverStartedNotice() {
        let meeting = CalendarEvent(day: today, startMinute: 10 * 60, title: "会議")
        let visit = CalendarEvent(day: today, startMinute: 10 * 60 + 30, title: "A社")
        // A社へは 10:01 に出る必要がある（出発時刻の計算は第 5 段階。ここでは渡すだけ）
        let departure: (CalendarEvent) -> Date? = { $0.id == visit.id ? self.at(self.today, 10 * 60 + 1) : nil }
        XCTAssertEqual(HomeSchedule.main(in: [meeting, visit], now: at(today, 10 * 60), departure: departure), .started(meeting))
        XCTAssertEqual(HomeSchedule.main(in: [meeting, visit], now: at(today, 10 * 60 + 1), departure: departure), .upcoming(visit),
                       "3 分たつ前でも、次の予定の出発が必要になったらそちらを優先する（最大 3 分）")
    }

    func testQuietWhenSixtyMinutesOrMoreAway() {
        let now = at(today, 9 * 60)
        XCTAssertTrue(HomeSchedule.isQuiet(now: now, start: at(today, 10 * 60)), "60 分以上先は静かに出す")
        XCTAssertFalse(HomeSchedule.isQuiet(now: now, start: at(today, 9 * 60 + 59)))
    }
}
