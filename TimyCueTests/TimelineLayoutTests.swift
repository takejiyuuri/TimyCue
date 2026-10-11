import XCTest
@testable import TimyCue

final class TimelineLayoutTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 12)

    private func event(_ title: String, _ start: MinuteOfDay, _ duration: Int?, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(day: day, startMinute: start, durationMinutes: duration, title: title, isAllDay: allDay)
    }

    private func placements(_ events: [CalendarEvent], minimumVisualMinutes: Double = 15) -> [UUID: TimelinePlacement] {
        TimelineLayout.placements(for: events, minimumVisualMinutes: minimumVisualMinutes)
    }

    func testSeparateEventsUseOneColumn() {
        let a = event("A", 540, 60)
        let b = event("B", 600, 30)
        let placements = self.placements([a, b])
        XCTAssertEqual(placements[a.id], TimelinePlacement(column: 0, columnCount: 1), "終わりと始まりが接しているだけなら重ならない")
        XCTAssertEqual(placements[b.id], TimelinePlacement(column: 0, columnCount: 1))
    }

    func testTwoOverlappingEventsSplitIntoTwoColumns() {
        let a = event("A", 570, 60)
        let b = event("B", 600, 60)
        let placements = self.placements([b, a])
        XCTAssertEqual(placements[a.id], TimelinePlacement(column: 0, columnCount: 2), "2 件なら左右 2 列（仕様 §29）")
        XCTAssertEqual(placements[b.id], TimelinePlacement(column: 1, columnCount: 2))
    }

    func testThreeOverlappingEventsSplitIntoThreeColumns() {
        let a = event("A", 570, 60)
        let b = event("B", 600, 60)
        let c = event("C", 615, nil)
        let placements = self.placements([a, b, c])
        XCTAssertEqual(placements.values.map(\.columnCount), [3, 3, 3], "3 件なら 3 列（仕様 §29）")
        XCTAssertEqual(Set(placements.values.map(\.column)), [0, 1, 2])
    }

    func testChainReusesFreedColumn() {
        // A と B、B と C は重なるが、A と C は重ならない → 2 列で足りる
        let a = event("A", 540, 60)
        let b = event("B", 570, 60)
        let c = event("C", 600, 30)
        let placements = self.placements([a, b, c])
        XCTAssertEqual(placements[a.id], TimelinePlacement(column: 0, columnCount: 2))
        XCTAssertEqual(placements[b.id], TimelinePlacement(column: 1, columnCount: 2))
        XCTAssertEqual(placements[c.id], TimelinePlacement(column: 0, columnCount: 2), "空いた左の列を使う")
    }

    func testEventWithoutEndUsesVisualHeightOnly() {
        let a = event("終了なし", 600, nil)
        let b = event("B", 610, 30)
        let c = event("C", 640, 30)

        // 標準の倍率：低い固定の高さのブロックが、10 分後の予定に見た目で重なる → 横に分ける
        let standard = self.placements([a, b, c], minimumVisualMinutes: 22)
        XCTAssertEqual(standard[a.id]?.columnCount, 2, "見た目で重なるなら横に分ける")
        XCTAssertEqual(standard[c.id], TimelinePlacement(column: 0, columnCount: 1), "重なりが切れたら 1 列に戻る")

        // 大きく拡大：同じ高さのブロックが 5 分ぶんにしかならない → 重ならないので分けない
        let zoomed = self.placements([a, b, c], minimumVisualMinutes: 5)
        XCTAssertEqual(zoomed[a.id], TimelinePlacement(column: 0, columnCount: 1),
                       "終了時刻のない予定を 15 分の予定として扱わない。見た目の高さだけで判断する（Q15）")
        XCTAssertNil(a.durationMinutes, "並べ方は終了時刻を作らない")
    }

    func testMinimumVisualMinutesFollowsZoom() {
        XCTAssertEqual(TimelineLayout.minimumVisualMinutes(blockHeight: 22, hourHeight: 60), 22, accuracy: 0.001)
        XCTAssertEqual(TimelineLayout.minimumVisualMinutes(blockHeight: 22, hourHeight: 240), 5.5, accuracy: 0.001,
                       "拡大すると同じ高さでも短い時間ぶんになる")
    }

    func testMinuteUnderFinger() {
        XCTAssertEqual(TimelineLayout.minute(atContentY: 10 + 90, hourHeight: 60, topInset: 10), 90, accuracy: 0.001,
                       "中身の上から 100pt（余白 10pt）は 1:30（Q16 のピンチの中心）")
        XCTAssertEqual(TimelineLayout.minute(atContentY: 10 + 90, hourHeight: 120, topInset: 10), 45, accuracy: 0.001)
        XCTAssertEqual(TimelineLayout.minute(atContentY: -50, hourHeight: 60, topInset: 10), 0, "上にはみ出したら 0:00")
    }

    func testPinchMarkerRoundsToFiveMinutes() {
        XCTAssertEqual(TimelineAnchor.marker(nearest: 92.4), "minute-90")
        XCTAssertEqual(TimelineAnchor.marker(nearest: 93), "minute-95")
        XCTAssertEqual(TimelineAnchor.marker(nearest: 2000), "minute-1440")
    }

    func testAllDayEventsAreNotPlacedOnTimeline() {
        let allDay = event("終日", 0, nil, allDay: true)
        let a = event("A", 0, 30)
        let placements = self.placements([allDay, a])
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

        let event = store.timedEvents(on: today)[0]
        store.openEventDetail(event.id)
        XCTAssertEqual(store.path, [.timeline(today), .eventDetail(event.id)],
                       "予定ブロックを押すと予定詳細へ。3 分割画面へは直接行かない（Q17）")
        XCTAssertEqual(store.event(id: event.id)?.title, "A")
        XCTAssertEqual(store.timedEvents(on: today).map(\.title), ["A"])
        XCTAssertEqual(store.allDayEvents(on: today).map(\.title), ["終日"], "終日は上の専用帯へ（仕様 §30）")
    }
}

final class EventDetailRowsTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 12)

    func testRowsForCarEvent() {
        let event = CalendarEvent(day: day, startMinute: 570, durationMinutes: 60, title: "A社打合せ", locationName: "広島市中区")
        var info = TimyCueEventMetadata()
        info.arrivalTargetMinutes = 10
        info.transport = .car
        info.route = .preferHighway
        let rows = EventDetailRows(event: event, metadata: info)
        XCTAssertEqual(rows.dateTime, "10月12日（月） 9:30–10:30")
        XCTAssertEqual(rows.place, "広島市中区")
        XCTAssertEqual(rows.arrivalTarget, "10分前")
        XCTAssertEqual(rows.transport, "車")
        XCTAssertEqual(rows.route, "高速優先", "ルートは車のときだけ（仕様 §52）")
        XCTAssertEqual(rows.notifications, "30分・10分・出発")
    }

    func testRowsForEventWithoutPlaceOrMetadata() {
        let event = CalendarEvent(day: day, startMinute: 600, title: "", source: .appleCalendar)
        let rows = EventDetailRows(event: event, metadata: nil)
        XCTAssertEqual(rows.dateTime, "10月12日（月） 10:00", "終了未設定なら開始だけ")
        XCTAssertNil(rows.place)
        XCTAssertEqual(rows.arrivalTarget, "未設定")
        XCTAssertEqual(rows.transport, "自動")
        XCTAssertNil(rows.route)
    }

    func testAllDayAndMapsURL() {
        let event = CalendarEvent(day: day, startMinute: 0, title: "休み", isAllDay: true)
        XCTAssertEqual(EventDetailRows(event: event, metadata: nil).dateTime, "10月12日（月） 終日")
        let url = EventDetailRows.mapsURL(for: "広島駅 南口")
        XCTAssertEqual(url?.host, "maps.apple.com", "場所は外部の地図へ渡す（v1.1）")
        XCTAssertEqual(URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "広島駅 南口")
    }
}
