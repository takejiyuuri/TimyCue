import EventKit
import XCTest
@testable import TimyCue

/// TestFlight 1.0 (30) から、この版へ更新したとき（2026-10-19）：1.0 (30) が書いた設定のファイル（formatVersion 2・saveTargetKind・
/// appleLinkEnabled・defaultCalendarID・hiddenCalendarIDs・祝日の手直しなど）と、移行の済んだ記録（UserDefaults の
/// TimyCue.SaveTargetRecord.v1。テストでは差し替えた保存先）のまま起動しても、設定の値を変えず、設定のファイルを書き直さず
/// （中身のバイトも書いた時刻も同じ）、移行をやり直さず、予定・TimyCue の設定・結び付けのファイルにも触れない
final class UpdateFromBuild30Tests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 19)
    private let defaultCalendar = CalendarChoice(id: "default", title: "Default", sourceTitle: "iCloud", isWritable: true, color: .orange)
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green)
    private let work = CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue)
    private var files: AppFiles!
    private var suiteName: String!
    private var defaults: UserDefaults!

    /// 1.0 (30) で連携 ON・保存先に「仕事」をはっきり選び、表示・祝日を手で直し、重複候補も扱った人の設定
    private let linkedJSON = #"{"defaultCalendarID":"work","hiddenCalendarIDs":["jp"],"guidanceDismissCount":1,"keptBothDuplicates":["a|b"],"notifiedDuplicates":["a|b"],"holidayOverrides":{"memo":true},"saveTargetKind":"appleCalendar","formatVersion":2}"#
    /// 1.0 (30) で連携を OFF にした人の設定（保存先は TimyCue のみ）
    private let offJSON = #"{"hiddenCalendarIDs":[],"saveTargetKind":"timyCueOnly","appleLinkEnabled":false,"formatVersion":2}"#
    /// 1.0 (30) で保存先に「Default」をはっきり選び、その表示を OFF にした人の設定（1.0 (30) で作成画面を開くと落ちた形）
    private let hiddenDefaultJSON = #"{"defaultCalendarID":"default","hiddenCalendarIDs":["default"],"saveTargetKind":"appleCalendar","appleLinkEnabled":true,"formatVersion":2}"#

    override func setUpWithError() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        files = AppFiles(folder: folder)
        suiteName = "TimyCueTests.UpdateFromBuild30.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: files.folder)
    }

    private var records: SaveTargetRecordStore { SaveTargetRecordStore(defaults: defaults) }

    /// 移行の済んだ記録のバイト（UserDefaults の TimyCue.SaveTargetRecord.v1）
    private var recordBytes: Data? { defaults.data(forKey: SaveTargetRecordStore.defaultKey) }

    /// 1.0 (30) の設定のファイルと移行の済んだ記録、予定・TimyCue の設定・結び付けのファイル（Apple へ書いた跡のある利用者）を置く
    private func writeBuild30Files(preferences json: String, record: SaveTargetRecord) throws {
        try Data(json.utf8).write(to: files.preferences)
        records.save(record)
        let linkedID = UUID()
        var links = EventKitLinks()
        links.keys[linkedID] = "item-1"
        links.endUnset = [linkedID]
        links.seriesIDs = ["item-S": UUID()]
        try JSONEncoder().encode(links).write(to: files.links)
        try JSONEncoder().encode([CalendarEvent(day: day, startMinute: 600, title: "歯医者")]).write(to: files.events)
        var settings = TimyCueEventMetadata()
        settings.arrivalTargetMinutes = 15
        try JSONEncoder().encode([linkedID: settings]).write(to: files.metadata)
    }

    private var watched: [URL] { [files.preferences, files.events, files.metadata, files.links] }

    /// 本物の EventKit の保存先（結び付けは一時ファイル。Apple の予定は読み書きしない）で起動する
    @MainActor
    private func launchWithEventKit(authorization: EKAuthorizationStatus, created: CallCount) -> CalendarConnection {
        let local = FileEventRepository(file: JSONFile(url: files.events, empty: []))
        let metadata = FileEventMetadataRepository(file: JSONFile(url: files.metadata, empty: [:]))
        let linksURL = files.links
        return CalendarConnection(eventStore: EKEventStore(), switchable: SwitchableEventRepository(local), localEvents: local,
                                  metadata: metadata,
                                  preferencesFile: JSONFile(url: files.preferences, empty: CalendarPreferences()),
                                  saveTargetRecords: records,
                                  authorizationStatus: { authorization },
                                  makeAppleRepository: { preferences, journal in
                                      created.value += 1
                                      return EventKitEventRepository(store: EKEventStore(), metadata: metadata, preferences: preferences,
                                                                     journal: journal,
                                                                     linksFile: JSONFile(url: linksURL, empty: EventKitLinks()))
                                  },
                                  onChange: { _, _, _ in })
    }

    @MainActor
    func testALinkedUserIsUpdatedWithoutRewritingAnything() throws {
        try writeBuild30Files(preferences: linkedJSON, record: SaveTargetRecord(kind: .appleCalendar, calendarID: "work", linkEnabled: nil))
        let before = watched.map { files.bytes($0) }
        let modified = watched.map { files.modified($0) }
        let record = recordBytes
        let expected = try JSONDecoder().decode(CalendarPreferences.self, from: Data(linkedJSON.utf8))

        let created = CallCount()
        let connection = launchWithEventKit(authorization: .fullAccess, created: created)
        XCTAssertEqual(connection.preferences, expected, "設定の値を変えない（表示・祝日の手直し・重複候補の扱いも）")
        XCTAssertFalse(connection.isLinkSettingUnconfirmed)
        XCTAssertTrue(connection.isLinked)
        XCTAssertEqual(created.value, 1, "連携 ON のままなので、今までどおり Apple カレンダーの保存先を使う")
        XCTAssertNil(connection.settingsFailure)
        XCTAssertEqual(watched.map { files.bytes($0) }, before, "設定・予定・TimyCue の設定・結び付けのファイルを書き直さない")
        XCTAssertEqual(watched.map { files.modified($0) }, modified)
        XCTAssertEqual(recordBytes, record, "移行の済んだ記録も書き直さない（移行をやり直さない）")

        // 前面に戻っても同じ
        connection.handleBecameActive()
        XCTAssertEqual(watched.map { files.bytes($0) }, before)
        XCTAssertEqual(recordBytes, record)
    }

    @MainActor
    func testAUserWhoTurnedTheLinkOffIsUpdatedWithTheLinkStillOff() throws {
        try writeBuild30Files(preferences: offJSON, record: SaveTargetRecord(kind: .timyCueOnly, calendarID: nil, linkEnabled: false))
        let before = watched.map { files.bytes($0) }
        let modified = watched.map { files.modified($0) }
        let record = recordBytes
        let expected = try JSONDecoder().decode(CalendarPreferences.self, from: Data(offJSON.utf8))

        for authorization in [EKAuthorizationStatus.fullAccess, .denied, .notDetermined] {
            let created = CallCount()
            let connection = launchWithEventKit(authorization: authorization, created: created)
            XCTAssertEqual(connection.preferences, expected, "許可 \(authorization.rawValue)：設定の値を変えない")
            XCTAssertEqual(connection.preferences.saveTargetKind, .timyCueOnly,
                           "Apple へ書いた跡（結び付けの終了未設定の印）があっても、移行をやり直さない")
            XCTAssertEqual(connection.linkStatus, .off, "OFF のまま（黙って ON にしない）")
            XCTAssertEqual(created.value, 0, "EventKit の保存先を作らない（結び付けのファイルも読まない）")
            XCTAssertEqual(watched.map { files.bytes($0) }, before)
            XCTAssertEqual(watched.map { files.modified($0) }, modified)
            XCTAssertEqual(recordBytes, record)
        }
    }

    @MainActor
    func testAUserWithAHiddenExplicitDefaultKeepsItHiddenAndNothingIsWritten() throws {
        try writeBuild30Files(preferences: hiddenDefaultJSON, record: SaveTargetRecord(kind: .appleCalendar, calendarID: "default", linkEnabled: true))
        let before = watched.map { files.bytes($0) }
        let record = recordBytes
        let expected = try JSONDecoder().decode(CalendarPreferences.self, from: Data(hiddenDefaultJSON.utf8))

        // Apple カレンダーの代わりの保存先（見えるカレンダーを決める）と、アプリと同じつなぎ方の作成画面
        let apple = AppleCalendarStub(calendars: [defaultCalendar, home, work], systemDefaultID: "default")
        let local = FileEventRepository(file: JSONFile(url: files.events, empty: []))
        let switchable = SwitchableEventRepository(local)
        let editor = ScheduleEditorStore(repository: switchable, metadataRepository: InMemoryEventMetadataRepository())
        let connection = CalendarConnection(eventStore: EKEventStore(), switchable: switchable, localEvents: local,
                                            metadata: InMemoryEventMetadataRepository(),
                                            preferencesFile: JSONFile(url: files.preferences, empty: CalendarPreferences()),
                                            saveTargetRecords: records,
                                            authorizationStatus: { .fullAccess },
                                            makeAppleRepository: { _, _ in
                                                apple.makeCount += 1
                                                return apple
                                            },
                                            onChange: { _, rules, status in
                                                editor.refresh()
                                                editor.receiveLink(rules, status: status)
                                            })
        XCTAssertEqual(connection.preferences, expected, "表示 OFF の Default を ON に戻さず、既定も変えない")
        XCTAssertTrue(connection.isLinked)

        editor.startNew(on: day)
        XCTAssertEqual(editor.pendingSaveTarget, .unavailable(.hidden(calendarTitle: "Default"), source: .settingsDefault))
        XCTAssertEqual(editor.calendarRowValues, ["Default（使えません）", "使えません"], "行の値の候補が重ならない（1.0 (30) のクラッシュの形）")
        editor.content.title = "A社"
        editor.setStartMinute(600)
        XCTAssertNotNil(editor.saveTargetPrompt, "保存の前に選び直してもらう")
        XCTAssertThrowsError(try editor.save())
        XCTAssertEqual(apple.writes, 0, "使えない保存先へも、ほかのカレンダーへも書かない")
        XCTAssertEqual(local.allEvents().map(\.title), ["歯医者"], "この iPhone の中にも書かない")

        XCTAssertEqual(connection.preferences, expected)
        XCTAssertEqual(watched.map { files.bytes($0) }, before, "設定・予定・TimyCue の設定・結び付けのファイルを書き直さない")
        XCTAssertEqual(recordBytes, record)
    }
}
