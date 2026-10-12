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
}
