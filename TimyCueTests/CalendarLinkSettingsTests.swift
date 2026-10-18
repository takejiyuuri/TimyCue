import EventKit
import XCTest
@testable import TimyCue

final class CalendarLinkSettingsTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 12)
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .orange)
    private let work = CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue)
    private let holidays = CalendarChoice(id: "jp", title: "日本の祝日", sourceTitle: "その他", isWritable: false, color: .green)

    // MARK: - 保存先（Q32。2026-10-17・2026-10-18 に spec §89 で変更）

    func testSaveTargetOrder() {
        var preferences = CalendarPreferences()
        func resolve(_ eventCalendarID: String?) -> SaveTargetResolution {
            SaveTargetRules(calendars: [home, work, holidays], preferences: preferences, systemDefaultID: "home")
                .resolve(eventCalendarID: eventCalendarID)
        }
        XCTAssertEqual(resolve(nil), .usable(home, source: .systemDefault), "初めは iPhone の「新規イベントのデフォルトカレンダー」")
        preferences.defaultCalendarID = "work"
        XCTAssertEqual(resolve(nil), .usable(work, source: .settingsDefault), "TimyCue の設定で既定の保存先を変えられる")
        XCTAssertEqual(resolve("home"), .usable(home, source: .event), "その予定だけの保存先がいちばん優先")
        XCTAssertEqual(resolve("jp"), .unavailable(.readOnly(calendarTitle: "日本の祝日"), source: .event),
                       "書き込めないカレンダーには保存しない。ほかのカレンダーへも勝手に移らない")
    }

    // MARK: - 既定の保存先が使えなくなったとき（v1.2 の自動の切り替えは 2026-10-17 に廃止。spec §89.4）

    func testUnavailableDefaultIsNotSwitchedToTheIPhoneDefault() {
        var preferences = CalendarPreferences()
        preferences.defaultCalendarID = "gone"
        let rules = SaveTargetRules(calendars: [home, work], preferences: preferences, systemDefaultID: "work")
        XCTAssertEqual(rules.resolve(eventCalendarID: nil), .unavailable(.notFound, source: .settingsDefault),
                       "削除された既定の保存先へは保存しない。iPhone の既定へも勝手に切り替えない")
        XCTAssertEqual(rules.preferences.defaultCalendarID, "gone", "既定の値は消さない（S2 の移行の手がかり）")
        XCTAssertNil(rules.preferences.pendingFallbackNotice, "切り替えの知らせの印も付けない")
    }

    func testReadOnlyDefaultIsReportedNotReplaced() {
        var preferences = CalendarPreferences()
        preferences.defaultCalendarID = "jp"
        let rules = SaveTargetRules(calendars: [home, holidays], preferences: preferences, systemDefaultID: "home")
        XCTAssertEqual(rules.resolve(eventCalendarID: nil), .unavailable(.readOnly(calendarTitle: "日本の祝日"), source: .settingsDefault),
                       "書き込めなくなったカレンダーは、理由を出して止める")
    }

    func testAvailableDefaultIsKept() {
        var preferences = CalendarPreferences()
        preferences.defaultCalendarID = "work"
        XCTAssertEqual(SaveTargetRules(calendars: [home, work], preferences: preferences, systemDefaultID: "home")
            .resolve(eventCalendarID: nil), .usable(work, source: .settingsDefault))
        XCTAssertEqual(SaveTargetRules(calendars: [], preferences: preferences, systemDefaultID: nil)
            .resolve(eventCalendarID: nil), .unavailable(.notFound, source: .settingsDefault),
                       "カレンダーが 1 つも見えないときも、既定を消さず、別へ移らない")
        XCTAssertEqual(preferences.defaultCalendarID, "work")
    }

    // MARK: - 設定トップの状態（v1.2「設定画面」）

    @MainActor
    func testStatusLabels() {
        XCTAssertEqual(CalendarConnection.statusLabel(for: .fullAccess), "接続済み")
        XCTAssertEqual(CalendarConnection.statusLabel(for: .notDetermined), "未接続")
        XCTAssertEqual(CalendarConnection.statusLabel(for: .writeOnly), "一部許可", "予定の追加だけ許可されている")
        XCTAssertEqual(CalendarConnection.statusLabel(for: .denied), "許可が必要")
        XCTAssertEqual(CalendarConnection.statusLabel(for: .restricted), "利用できません")
    }

    @MainActor
    func testCalendarRowOnlyWithTwoOrMoreUsableCalendars() {
        let store = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository())
        store.startNew(on: day)
        XCTAssertFalse(store.visibleRows.contains(.calendar), "つないでいないときは出さない")
        store.setCalendars(SaveTargetRules(calendars: [home, holidays], systemDefaultID: "home"))
        XCTAssertFalse(store.visibleRows.contains(.calendar), "使える保存先が 1 つだけなら出さない（Q32。表示のみ・書き込めないものは数えない）")
        var hidden = CalendarPreferences()
        hidden.hiddenCalendarIDs = ["work"]
        store.setCalendars(SaveTargetRules(calendars: [home, work], preferences: hidden, systemDefaultID: "home"))
        XCTAssertFalse(store.visibleRows.contains(.calendar), "表示 OFF のカレンダーも数えない")
        store.setCalendars(SaveTargetRules(calendars: [home, work], systemDefaultID: "home"))
        XCTAssertTrue(store.visibleRows.contains(.calendar), "2 つ以上なら出す")
        XCTAssertEqual(store.valueText(for: .calendar), "iPhoneの既定（家）", "初めは既定の保存先。実際の名前を添える（Q106）")
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

    // MARK: - 案内（Q38）

    @MainActor
    func testGuidanceShownOnceThenOnceMoreBeforeSavingThenNotAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = FileEventRepository(file: JSONFile(url: directory.appendingPathComponent("events.json"), empty: []))
        let connection = CalendarConnection(
            eventStore: EKEventStore(),
            switchable: SwitchableEventRepository(local),
            localEvents: local,
            metadata: InMemoryEventMetadataRepository(),
            preferencesFile: JSONFile(url: directory.appendingPathComponent("prefs.json"), empty: CalendarPreferences()),
            onChange: { _, _ in })
        guard connection.state == .notAsked else { throw XCTSkip("このシミュレータではカレンダーの許可がもう決まっている") }

        XCTAssertTrue(connection.showsFirstGuidance, "初回は理由と「カレンダーを連携」を案内する（開いただけで許可のダイアログは出さない）")
        XCTAssertFalse(connection.showsGuidanceBeforeSaving)

        connection.dismissGuidance()
        XCTAssertFalse(connection.showsFirstGuidance)
        XCTAssertTrue(connection.showsGuidanceBeforeSaving, "「あとで」にしたら、新しい予定を保存するときにもう一度案内する")

        connection.dismissGuidance()
        XCTAssertFalse(connection.showsFirstGuidance)
        XCTAssertFalse(connection.showsGuidanceBeforeSaving, "何度も自分からは案内しない")
    }

    @MainActor
    func testSampleDataNeverAsks() {
        let connection = CalendarConnection(
            eventStore: EKEventStore(),
            switchable: SwitchableEventRepository(InMemoryEventRepository()),
            localEvents: nil,
            metadata: InMemoryEventMetadataRepository(),
            preferencesFile: JSONFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), empty: CalendarPreferences()),
            onChange: { _, _ in })
        XCTAssertFalse(connection.isLive)
        XCTAssertFalse(connection.showsFirstGuidance, "見本の予定で動いているときは案内も出さず、つながない（Q34）")
    }

    func testOldPreferencesFileStillLoads() throws {
        let json = #"{"hiddenCalendarIDs":["jp"]}"#
        let preferences = try JSONDecoder().decode(CalendarPreferences.self, from: Data(json.utf8))
        XCTAssertNil(preferences.guidanceDismissCount)
        XCTAssertNil(preferences.pendingFallbackNotice)
        XCTAssertFalse(preferences.isShown("jp"))
    }
}
