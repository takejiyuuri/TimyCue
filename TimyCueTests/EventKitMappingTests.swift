import EventKit
import XCTest
@testable import TimyCue

final class EventKitMappingTests: XCTestCase {
    private let calendar = Calendar.timyCue
    private let day = CalendarDay(year: 2026, month: 10, day: 12)

    func testEventWithEndRoundTrips() {
        let event = CalendarEvent(day: day, startMinute: 570, durationMinutes: 60, title: "A社打合せ",
                                  locationName: "広島市中区", notes: "資料")
        let record = EventKitMapping.record(from: event, calendar: calendar)
        XCTAssertEqual(record.startDate, day.date(atMinute: 570, calendar: calendar))
        XCTAssertEqual(record.endDate, day.date(atMinute: 630, calendar: calendar))
        XCTAssertEqual(record.notes, "資料", "メモは消さない（§55）")

        let back = EventKitMapping.calendarEvent(from: record, id: event.id, endIsUnset: false, source: .timyCue, calendar: calendar)
        XCTAssertEqual(back, event)
    }

    func testEventWithoutEndIsSavedWithTenMinutesButStaysUnset() {
        let event = CalendarEvent(day: day, startMinute: 600, title: "電話")
        let record = EventKitMapping.record(from: event, calendar: calendar)
        XCTAssertEqual(record.endDate.timeIntervalSince(record.startDate), 10 * 60,
                       "Apple カレンダーには開始＋10 分で保存する（§69）")
        let back = EventKitMapping.calendarEvent(from: record, id: event.id, endIsUnset: true, source: .timyCue, calendar: calendar)
        XCTAssertNil(back.durationMinutes, "この 10 分を実際の終了として扱わない（§69）")
        XCTAssertNil(back.endMinute)
    }

    func testAllDayEvent() {
        let event = CalendarEvent(day: day, startMinute: 0, title: "休み", isAllDay: true)
        let record = EventKitMapping.record(from: event, calendar: calendar)
        XCTAssertTrue(record.isAllDay)
        XCTAssertEqual(record.endDate, day.adding(days: 1).date(calendar: calendar))
        let back = EventKitMapping.calendarEvent(from: record, id: event.id, endIsUnset: false, source: .appleCalendar, calendar: calendar)
        XCTAssertEqual(back.day, day)
        XCTAssertTrue(back.isAllDay)
        XCTAssertNil(back.durationMinutes)
    }

    func testUntitledAppleCalendarEvent() {
        let record = ExternalEventRecord(title: "", location: "広島駅",
                                         startDate: day.date(atMinute: 600, calendar: calendar),
                                         endDate: day.date(atMinute: 660, calendar: calendar),
                                         isAllDay: false, notes: nil)
        let event = EventKitMapping.calendarEvent(from: record, id: UUID(), endIsUnset: false, source: .appleCalendar, calendar: calendar)
        XCTAssertEqual(event.displayTitle, "広島駅", "名前のない予定はそのまま持ち、表示は場所名（Q3・Q4）")
        XCTAssertEqual(event.source, .appleCalendar)
        XCTAssertEqual(event.durationMinutes, 60)
    }

    func testLinkKeysForRecurringOccurrences() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(EventKitMapping.linkKey(itemIdentifier: "abc", occurrenceDate: nil), "abc")
        let key = EventKitMapping.linkKey(itemIdentifier: "abc", occurrenceDate: date)
        XCTAssertEqual(key, "abc|1800000000", "繰り返しの予定は回ごとに見分ける")
        let parsed = EventKitMapping.parseLinkKey(key)
        XCTAssertEqual(parsed.itemIdentifier, "abc")
        XCTAssertEqual(parsed.occurrenceDate, date)
        XCTAssertNil(EventKitMapping.parseLinkKey("abc").occurrenceDate)

        var links = EventKitLinks()
        let id = UUID()
        links.keys[id] = key
        XCTAssertEqual(links.id(forKey: key), id)
    }

    // MARK: - 足りない範囲だけを読む（裏での読み込み）

    func testMissingRangesReadOnlyWhatIsNotRequestedYet() {
        let d = { (offset: Int) in CalendarDay(year: 2026, month: 10, day: 1).adding(days: offset) }
        XCTAssertEqual(EventKitMapping.missingRanges(wanted: d(0)...d(10), requested: nil), [d(0)...d(10)], "初めは全部")
        XCTAssertEqual(EventKitMapping.missingRanges(wanted: d(2)...d(8), requested: d(0)...d(10)), [], "読んである範囲なら何もしない")
        XCTAssertEqual(EventKitMapping.missingRanges(wanted: d(-5)...d(3), requested: d(0)...d(10)), [d(-5)...d(-1)],
                       "過去へスクロールしたら、前に足した分だけ")
        XCTAssertEqual(EventKitMapping.missingRanges(wanted: d(8)...d(20), requested: d(0)...d(10)), [d(11)...d(20)],
                       "未来へは、後ろに足した分だけ")
        XCTAssertEqual(EventKitMapping.missingRanges(wanted: d(-3)...d(13), requested: d(0)...d(10)), [d(-3)...d(-1), d(11)...d(13)])
        XCTAssertEqual(EventKitMapping.missingRanges(wanted: d(-30)...d(-20), requested: d(0)...d(10)), [d(-30)...d(-1)],
                       "離れた範囲なら、間も読んで途切れないようにする")
    }

    func testNearestColorUsesHue() {
        XCTAssertEqual(EventColor.nearest(red: 1, green: 0.58, blue: 0), .orange, "Apple カレンダーのオレンジ（§53）")
        XCTAssertEqual(EventColor.nearest(red: 0.4, green: 0.8, blue: 0.3), .green)
        XCTAssertEqual(EventColor.nearest(red: 0, green: 0.48, blue: 1), .saxeBlue, "Apple カレンダーの青")
        XCTAssertEqual(EventColor.nearest(red: 0.69, green: 0.32, blue: 0.87), .lavender, "紫")
        XCTAssertEqual(EventColor.nearest(red: 1, green: 0.8, blue: 0), .yellow)
    }

    @MainActor
    func testConnectionStates() {
        XCTAssertEqual(CalendarConnection.state(for: .notDetermined), .notAsked, "初めは求めていない（§79）")
        XCTAssertEqual(CalendarConnection.state(for: .fullAccess), .connected)
        XCTAssertEqual(CalendarConnection.state(for: .denied), .denied)
        XCTAssertEqual(CalendarConnection.state(for: .writeOnly), .denied, "読めないと同期できないので、つないでいない扱い")
        XCTAssertEqual(CalendarConnection.state(for: .restricted), .restricted)
    }
}

final class FileRepositoryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testEventsSurviveRestart() throws {
        let file = JSONFile<[CalendarEvent]>(url: directory.appendingPathComponent("events.json"), empty: [])
        let event = CalendarEvent(day: CalendarDay(year: 2026, month: 10, day: 12), startMinute: 600, title: "A社")
        try FileEventRepository(file: file).insert([event])

        let reopened = FileEventRepository(file: file)
        XCTAssertEqual(reopened.allEvents(), [event], "アプリを閉じても残る")
        var moved = event
        moved.startMinute = 660
        try reopened.update(moved)
        XCTAssertEqual(FileEventRepository(file: file).allEvents().first?.startMinute, 660)
        try reopened.delete(id: event.id)
        XCTAssertTrue(FileEventRepository(file: file).allEvents().isEmpty)
    }

    func testMetadataSurvivesRestart() throws {
        let file = JSONFile<[UUID: TimyCueEventMetadata]>(url: directory.appendingPathComponent("metadata.json"), empty: [:])
        let id = UUID()
        var info = TimyCueEventMetadata()
        info.transport = .bicycle
        info.notifications = NotificationPreference(timings: [.beforeStart(minutes: 15)])
        try FileEventMetadataRepository(file: file).save(info, for: id)
        XCTAssertEqual(FileEventMetadataRepository(file: file).allMetadata()[id], info)
    }

    func testMetadataSaveAllKeepsOthers() throws {
        let file = JSONFile<[UUID: TimyCueEventMetadata]>(url: directory.appendingPathComponent("metadata.json"), empty: [:])
        let repository = FileEventMetadataRepository(file: file)
        let kept = UUID()
        var walk = TimyCueEventMetadata()
        walk.transport = .walk
        try repository.save(walk, for: kept)

        var entries: [UUID: TimyCueEventMetadata] = [:]
        for _ in 0..<300 {
            var info = TimyCueEventMetadata()
            info.color = .mint
            entries[UUID()] = info
        }
        try repository.saveAll(entries)
        let reopened = FileEventMetadataRepository(file: file).allMetadata()
        XCTAssertEqual(reopened.count, 301, "Apple カレンダーの予定を何百件も初めて読んでも、まとめて残る")
        XCTAssertEqual(reopened[kept], walk, "前からあったものは消さない")
    }

    func testBrokenFileStartsEmpty() throws {
        let url = directory.appendingPathComponent("events.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("壊れたファイル".utf8).write(to: url)
        XCTAssertTrue(FileEventRepository(file: JSONFile(url: url, empty: [])).allEvents().isEmpty,
                      "読めなくてもアプリを止めない（§80）")
    }

    func testSwitchableRepositoryForwardsToCurrent() throws {
        let first = InMemoryEventRepository()
        let second = InMemoryEventRepository()
        let switchable = SwitchableEventRepository(first)
        let event = CalendarEvent(day: CalendarDay(year: 2026, month: 10, day: 12), startMinute: 600, title: "A社")
        try switchable.insert([event])
        XCTAssertEqual(first.allEvents(), [event])
        switchable.use(second)
        XCTAssertTrue(switchable.allEvents().isEmpty, "つないだら新しい保存先を見る")
    }
}
