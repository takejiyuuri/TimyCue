import XCTest
@testable import TimyCue

final class TimelineLayoutTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 12)

    private func event(_ title: String, _ start: MinuteOfDay, _ duration: Int?, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(day: day, startMinute: start, durationMinutes: duration, title: title, isAllDay: allDay)
    }

    func testSeparateEventsUseOneColumn() {
        let a = event("A", 540, 60)
        let b = event("B", 600, 30)
        let placements = TimelineLayout.placements(for: [a, b])
        XCTAssertEqual(placements[a.id], TimelinePlacement(column: 0, columnCount: 1), "終わりと始まりが接しているだけなら重ならない")
        XCTAssertEqual(placements[b.id], TimelinePlacement(column: 0, columnCount: 1))
    }

    func testTwoOverlappingEventsSplitIntoTwoColumns() {
        let a = event("A", 570, 60)
        let b = event("B", 600, 60)
        let placements = TimelineLayout.placements(for: [b, a])
        XCTAssertEqual(placements[a.id], TimelinePlacement(column: 0, columnCount: 2), "2 件なら左右 2 列（仕様 §29）")
        XCTAssertEqual(placements[b.id], TimelinePlacement(column: 1, columnCount: 2))
    }

    func testThreeOverlappingEventsSplitIntoThreeColumns() {
        let a = event("A", 570, 60)
        let b = event("B", 600, 60)
        let c = event("C", 615, nil)
        let placements = TimelineLayout.placements(for: [a, b, c])
        XCTAssertEqual(placements.values.map(\.columnCount), [3, 3, 3], "3 件なら 3 列（仕様 §29）")
        XCTAssertEqual(Set(placements.values.map(\.column)), [0, 1, 2])
    }

    func testChainReusesFreedColumn() {
        // A と B、B と C は重なるが、A と C は重ならない → 2 列で足りる
        let a = event("A", 540, 60)
        let b = event("B", 570, 60)
        let c = event("C", 600, 30)
        let placements = TimelineLayout.placements(for: [a, b, c])
        XCTAssertEqual(placements[a.id], TimelinePlacement(column: 0, columnCount: 2))
        XCTAssertEqual(placements[b.id], TimelinePlacement(column: 1, columnCount: 2))
        XCTAssertEqual(placements[c.id], TimelinePlacement(column: 0, columnCount: 2), "空いた左の列を使う")
    }

    func testEventWithoutEndCountsAsShortBlock() {
        let a = event("終了なし", 600, nil)
        let b = event("B", 610, 30)
        let c = event("C", 640, 30)
        let placements = TimelineLayout.placements(for: [a, b, c])
        XCTAssertEqual(TimelineLayout.layoutEnd(of: a), 615, "終了のない予定は短いブロックとして扱う（仮に 15 分）")
        XCTAssertEqual(placements[a.id]?.columnCount, 2, "すぐあとの予定とは横に分ける")
        XCTAssertEqual(placements[c.id], TimelinePlacement(column: 0, columnCount: 1), "重なりが切れたら 1 列に戻る")
    }

    func testAllDayEventsAreNotPlacedOnTimeline() {
        let allDay = event("終日", 0, nil, allDay: true)
        let a = event("A", 0, 30)
        let placements = TimelineLayout.placements(for: [allDay, a])
        XCTAssertNil(placements[allDay.id], "終日の予定は 0:00〜24:00 を使わない（仕様 §30）")
        XCTAssertEqual(placements[a.id], TimelinePlacement(column: 0, columnCount: 1))
    }

    func testInitialMinute() {
        let events = [event("A", 600, 60), event("B", 540, 30), event("終日", 0, nil, allDay: true)]
        XCTAssertEqual(TimelineLayout.initialMinute(events: events, isToday: true, now: 14 * 60 + 18), 13 * 60 + 18,
                       "今日は現在時刻の少し前から")
        XCTAssertEqual(TimelineLayout.initialMinute(events: events, isToday: false, now: 0), 8 * 60,
                       "ほかの日は最初の予定の少し前から（終日は数えない）")
        XCTAssertEqual(TimelineLayout.initialMinute(events: [], isToday: false, now: 0), 8 * 60)
    }

    func testClockMinuteOfDay() {
        let date = CalendarDay(year: 2026, month: 10, day: 12).date(atMinute: 14 * 60 + 18)
        XCTAssertEqual(Clock.minuteOfDay(date), 858)
    }
}

@MainActor
final class CalendarTimelineStoreTests: XCTestCase {
    private let today = CalendarDay(year: 2026, month: 10, day: 12)

    func testOpenTimelineAndSplitAllDay() {
        let store = CalendarStore(
            repository: InMemoryEventRepository(events: [
                CalendarEvent(day: today, startMinute: 600, title: "A"),
                CalendarEvent(day: today, startMinute: 0, title: "終日", isAllDay: true),
            ]),
            metadataRepository: InMemoryEventMetadataRepository(),
            today: today)

        store.openTimeline(today)
        XCTAssertEqual(store.path, [.timeline(today)], "吹き出しの日付からその日のタイムラインへ（仕様 §25）")
        XCTAssertEqual(store.timedEvents(on: today).map(\.title), ["A"])
        XCTAssertEqual(store.allDayEvents(on: today).map(\.title), ["終日"], "終日は上の専用帯へ（仕様 §30）")
    }
}
