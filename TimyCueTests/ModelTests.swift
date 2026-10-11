import XCTest
@testable import TimyCue

final class ModelTests: XCTestCase {
    func testCalendarDayOrderingAndMonthBoundary() {
        let oct31 = CalendarDay(year: 2026, month: 10, day: 31)
        let nov1 = oct31.adding(days: 1)
        XCTAssertEqual(nov1, CalendarDay(year: 2026, month: 11, day: 1))
        XCTAssertLessThan(oct31, nov1)
        XCTAssertEqual(nov1.shortLabel, "11/1")
    }

    func testCalendarDayRoundTripsThroughDate() {
        let day = CalendarDay(year: 2026, month: 10, day: 12)
        XCTAssertEqual(CalendarDay(day.date(atMinute: 14 * 60 + 17)), day)
    }

    func testTimeText() {
        XCTAssertEqual(TimeText.hourMinute(857), "14:17")
        XCTAssertEqual(TimeText.hourMinute(0), "0:00")
    }

    func testPrimaryLabelFallsBackToPlace() {
        var content = EventContent()
        XCTAssertNil(content.primaryLabel)
        content.locationName = "広島駅"
        XCTAssertEqual(content.primaryLabel, "広島駅", "予定名がなければ場所名（仕様 §13）")
        content.title = "病院"
        XCTAssertEqual(content.primaryLabel, "病院")
    }

    func testNotificationSummary() {
        var settings = NotificationSettings()
        XCTAssertEqual(settings.summary, "30分・10分・出発")
        settings = NotificationSettings(thirtyMinutesBefore: false, tenMinutesBefore: false, atDeparture: false)
        XCTAssertEqual(settings.summary, "なし")
    }

    func testEndMinuteIsNilWithoutDuration() {
        let event = CalendarEvent(day: CalendarDay(year: 2026, month: 10, day: 12), startMinute: 600, content: EventContent())
        XCTAssertNil(event.endMinute, "終了未設定を仮の終了と取り違えない（仕様 §45）")
    }

    func testSampleEventsHaveNoPersonalPlaceholders() {
        let samples = SampleEvents.make(around: CalendarDay(year: 2026, month: 10, day: 12))
        XCTAssertFalse(samples.isEmpty)
        XCTAssertTrue(samples.contains { $0.isAllDay })
        XCTAssertTrue(samples.contains { $0.content.locationName == nil })
    }
}
