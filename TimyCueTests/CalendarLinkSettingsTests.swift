import XCTest
@testable import TimyCue

final class CalendarLinkSettingsTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 12)
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .orange)
    private let work = CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue)
    private let holidays = CalendarChoice(id: "jp", title: "日本の祝日", sourceTitle: "その他", isWritable: false, color: .green)

    // MARK: - 保存先（Q32）

    func testSaveTargetOrder() {
        let writable = [home, work]
        var preferences = CalendarPreferences()
        XCTAssertEqual(CalendarPreferences.saveTarget(eventCalendarID: nil, preferences: preferences,
                                                      systemDefaultID: "home", writable: writable), "home",
                       "初めは iPhone の「新規イベントのデフォルトカレンダー」")
        preferences.defaultCalendarID = "work"
        XCTAssertEqual(CalendarPreferences.saveTarget(eventCalendarID: nil, preferences: preferences,
                                                      systemDefaultID: "home", writable: writable), "work",
                       "TimyCue の設定で既定の保存先を変えられる")
        XCTAssertEqual(CalendarPreferences.saveTarget(eventCalendarID: "home", preferences: preferences,
                                                      systemDefaultID: "home", writable: writable), "home",
                       "その予定だけの保存先がいちばん優先")
        XCTAssertEqual(CalendarPreferences.saveTarget(eventCalendarID: "jp", preferences: CalendarPreferences(),
                                                      systemDefaultID: nil, writable: writable), "home",
                       "書き込めないカレンダーには保存しない")
    }

    @MainActor
    func testCalendarRowOnlyWithTwoOrMoreWritableCalendars() {
        let store = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository())
        store.startNew(on: day)
        XCTAssertFalse(store.visibleRows.contains(.calendar), "つないでいないときは出さない")
        store.setCalendars([home], defaultCalendarID: "home")
        XCTAssertFalse(store.visibleRows.contains(.calendar), "書き込めるカレンダーが 1 つだけなら出さない（Q32）")
        store.setCalendars([home, work], defaultCalendarID: "home")
        XCTAssertTrue(store.visibleRows.contains(.calendar), "2 つ以上なら出す")
        XCTAssertEqual(store.valueText(for: .calendar), "家", "初めは既定の保存先")
        store.content.calendarID = "work"
        XCTAssertEqual(store.valueText(for: .calendar), "仕事", "その予定だけ保存先を変えられる")
        store.content.title = "A社"
        store.setStartMinute(600)
        let saved = try? store.save()
        XCTAssertEqual(saved?.first?.calendarID, "work")
    }

    // MARK: - 読み込むカレンダー（Q33）

    func testAllCalendarsShownAtFirst() {
        var preferences = CalendarPreferences()
        XCTAssertTrue([home, work, holidays].allSatisfy { preferences.isShown($0.id) }, "初回は参照できるカレンダーをすべて読み込む")
        preferences.hiddenCalendarIDs.insert("jp")
        XCTAssertFalse(preferences.isShown("jp"), "設定から個別に OFF")
        XCTAssertTrue(preferences.isShown("home"))
    }

    // MARK: - 移さない（Q34）

    func testConnectingDoesNotMoveOrCopyLocalEvents() throws {
        let local = InMemoryEventRepository(events: [CalendarEvent(day: day, startMinute: 600, title: "端末の予定")])
        let apple = InMemoryEventRepository(events: [CalendarEvent(day: day, startMinute: 700, title: "Apple の予定")])
        let combined = CombinedEventRepository(primary: apple, local: local)

        XCTAssertEqual(Set(combined.allEvents().map(\.title)), ["端末の予定", "Apple の予定"], "両方を見せる")
        XCTAssertEqual(apple.allEvents().count, 1, "つないだだけで、端末の予定を Apple カレンダーへ移したり複製したりしない")

        let new = CalendarEvent(day: day, startMinute: 800, title: "新しい予定")
        try combined.insert([new])
        XCTAssertTrue(apple.allEvents().contains(new), "新しく作る予定は Apple カレンダーへ")
        XCTAssertEqual(local.allEvents().count, 1)

        var edited = local.allEvents()[0]
        edited.title = "端末の予定（直した）"
        try combined.update(edited)
        XCTAssertEqual(local.allEvents().first?.title, "端末の予定（直した）", "直すのはその予定がある方")
        XCTAssertFalse(apple.allEvents().contains { $0.id == edited.id })

        try combined.delete(id: edited.id)
        XCTAssertTrue(local.allEvents().isEmpty)
        XCTAssertEqual(apple.allEvents().count, 2)
    }

    // MARK: - 予定の保存先の持ち方

    func testEventKeepsCalendarAndOldFilesStillLoad() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社", calendarID: "work")
        XCTAssertEqual(EventContent(event: event, metadata: TimyCueEventMetadata()).calendarID, "work")
        XCTAssertEqual(EventContent(event: event, metadata: TimyCueEventMetadata())
            .makeEvent(day: day, startMinute: 600, durationMinutes: nil).calendarID, "work")

        // 保存先を持つ前のファイル（calendarID がない）も読める
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
        json["calendarID"] = nil
        let old = try JSONDecoder().decode(CalendarEvent.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.calendarID)
        XCTAssertEqual(old.title, "A社")
    }
}
