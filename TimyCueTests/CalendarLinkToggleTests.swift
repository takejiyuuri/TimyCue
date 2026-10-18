import EventKit
import XCTest
@testable import TimyCue

/// Apple カレンダー連携の ON/OFF（spec §89.6・§89.7・Q101〜Q104・Q115。S6）：
/// OFF で読み込みも書き込みも止める・Apple 側と TimyCue の設定は消さない・ON に戻すと同じ保存先を使い直して最新を取り直す
final class CalendarLinkToggleTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 19)
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green)
    private let work = CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue)
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var preferencesURL: URL { directory.appendingPathComponent("calendar-preferences.json") }

    /// 書けない場所（親がふつうのファイルなので、フォルダを作れない）
    private func unwritableURL(_ name: String) throws -> URL {
        let blocker = directory.appendingPathComponent("blocker-\(name)")
        try Data("x".utf8).write(to: blocker)
        return blocker.appendingPathComponent(name)
    }

    private func writePreferences(_ preferences: CalendarPreferences) throws {
        try JSONEncoder().encode(preferences).write(to: preferencesURL)
    }

    private func appleDefaultWork(linkEnabled: Bool? = nil) -> CalendarPreferences {
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = .appleCalendar
        preferences.defaultCalendarID = "work"
        preferences.hiddenCalendarIDs = ["jp"]
        preferences.setHoliday(true, calendarID: "memo")
        preferences.appleLinkEnabled = linkEnabled
        preferences.formatVersion = CalendarPreferences.currentFormatVersion
        return preferences
    }

    private struct Setup {
        let connection: CalendarConnection
        let local: FileEventRepository
        let switchable: SwitchableEventRepository
    }

    @MainActor
    private func makeConnection(apple: FakeAppleCalendar,
                                authorization: AuthorizationBox = AuthorizationBox(.fullAccess),
                                preferencesURL url: URL? = nil,
                                metadata: EventMetadataRepository = InMemoryEventMetadataRepository(),
                                journal: SaveJournal = .inMemory(),
                                records: SaveTargetRecordStore? = nil,
                                log: ChangeLog = ChangeLog(),
                                created: Counter = Counter()) -> Setup {
        let local = FileEventRepository(file: JSONFile(url: directory.appendingPathComponent("events.json"), empty: []))
        let switchable = SwitchableEventRepository(local)
        let connection = CalendarConnection(eventStore: EKEventStore(), switchable: switchable, localEvents: local,
                                            metadata: metadata,
                                            preferencesFile: JSONFile(url: url ?? preferencesURL, empty: CalendarPreferences()),
                                            journal: journal,
                                            saveTargetRecords: records,
                                            authorizationStatus: { authorization.status },
                                            makeAppleRepository: { _, _ in
                                                created.count += 1
                                                return apple
                                            },
                                            onChange: { _, rules in
                                                log.count += 1
                                                log.rules = rules
                                            })
        return Setup(connection: connection, local: local, switchable: switchable)
    }

    // MARK: - 状態の決まり（AppleLinkStatus）

    func testTheLinkStatusTellsOffFromNotLinked() {
        let table: [(EKAuthorizationStatus, Bool, AppleLinkStatus, String, Bool)] = [
            (.fullAccess, true, .linked, "接続済み", false),
            (.fullAccess, false, .off, "OFF", false),
            (.notDetermined, true, .notLinked, "未接続", true),
            (.notDetermined, false, .off, "OFF", false),
            (.denied, true, .needsPermission, "許可が必要", true),
            (.denied, false, .off, "OFF", false),
            (.writeOnly, true, .needsPermission, "一部許可", true),
            (.writeOnly, false, .off, "OFF", false),
            (.restricted, true, .unavailable, "利用できません", true),
            (.restricted, false, .off, "利用できません", false),
        ]
        for (authorization, enabled, expected, label, card) in table {
            let status = AppleLinkStatus.resolve(authorization: authorization, linkEnabled: enabled)
            XCTAssertEqual(status, expected, "許可 \(authorization.rawValue)・連携 \(enabled)")
            XCTAssertEqual(status.statusLabel(authorization: authorization), label, "設定トップの状態（OFF は「OFF」。Q102）")
            XCTAssertEqual(status.showsSetupCard, card,
                           "まだ連携していない・許可がないときは今の Home の案内（Q115）、わざと OFF にしたときは出さない（Q102）")
        }
    }

    func testOldSettingsAreLinked() throws {
        let old = try JSONDecoder().decode(CalendarPreferences.self, from: Data(#"{"hiddenCalendarIDs":[]}"#.utf8))
        XCTAssertTrue(old.isAppleLinkEnabled, "連携の ON/OFF を持たない前の版の設定は ON")
    }

    // MARK: - OFF

    @MainActor
    func testStartingWithTheLinkOffNeverTouchesAppleCalendar() throws {
        try writePreferences(appleDefaultWork(linkEnabled: false))
        let apple = FakeAppleCalendar(calendars: [home, work], systemDefaultID: "home")
        let log = ChangeLog()
        let created = Counter()
        let setup = makeConnection(apple: apple, log: log, created: created)
        let connection = setup.connection

        XCTAssertEqual(created.count, 0, "連携 OFF で起動したら、Apple カレンダーの保存先を作らない")
        XCTAssertTrue(setup.switchable.current === setup.local, "予定はこの iPhone の中だけ")
        XCTAssertFalse(connection.isLinked)
        XCTAssertTrue(connection.hasFullAccess, "iPhone の許可は変えない")
        XCTAssertEqual(connection.statusLabel, "OFF")
        XCTAssertFalse(connection.showsSetupCard, "わざと OFF にしたときは、連携を促すカードを出さない（Q102）")
        XCTAssertFalse(connection.showsFirstGuidance)
        XCTAssertTrue(connection.calendars.isEmpty)
        XCTAssertNil(log.rules)

        connection.calendarDidChange()
        connection.handleBecameActive()
        XCTAssertEqual(created.count, 0, "Apple カレンダー側が変わっても、前面に戻っても、OFF のあいだは触れない")
        XCTAssertEqual(apple.calendarReads, 0)
        XCTAssertTrue(connection.duplicateCandidates.isEmpty)
    }

    @MainActor
    func testTurningTheLinkOffStopsReadingAndWriting() throws {
        try writePreferences(appleDefaultWork())
        let apple = FakeAppleCalendar(calendars: [home, work], systemDefaultID: "home")
        let log = ChangeLog()
        let setup = makeConnection(apple: apple, log: log)
        let connection = setup.connection
        XCTAssertTrue(connection.isLinked)
        XCTAssertNotNil(log.rules, "連携中は保存先の決まりを作成画面へ渡す")
        XCTAssertFalse(setup.switchable.current === setup.local)

        XCTAssertTrue(connection.setAppleLinkEnabled(false))
        XCTAssertEqual(apple.pauses, 1, "Apple カレンダーの保存先を止める（捨てない）")
        XCTAssertTrue(setup.switchable.current === setup.local, "予定はこの iPhone の中だけ")
        XCTAssertNil(log.rules, "作成画面には、連携していないことを渡す（新しい予定は TimyCue のみ）")
        XCTAssertTrue(connection.calendars.isEmpty)
        XCTAssertTrue(connection.duplicateCandidates.isEmpty, "OFF のあいだは重複候補を出さない（Q102・Q104）")
        XCTAssertFalse(connection.showsDuplicateNotice)
        XCTAssertEqual(connection.statusLabel, "OFF")

        let reads = apple.calendarReads
        connection.calendarDidChange()
        connection.setShown(false, calendarID: "home")
        XCTAssertEqual(apple.calendarReads, reads, "OFF のあいだは Apple カレンダーを読まない")
        XCTAssertEqual(apple.reloads, 0)
    }

    @MainActor
    func testTurningTheLinkOffDeletesNothingAndKeepsTheSettings() throws {
        try writePreferences(appleDefaultWork())
        let metadataURL = directory.appendingPathComponent("metadata.json")
        let metadata = FileEventMetadataRepository(file: JSONFile(url: metadataURL, empty: [:]))
        var settings = TimyCueEventMetadata()
        settings.arrivalTargetMinutes = 15
        try metadata.save(settings, for: UUID())
        let journalURL = directory.appendingPathComponent("save-journal.json")
        let journal = SaveJournal(file: JSONFile(url: journalURL, empty: []))
        journal.begin([SaveJournalEntry(id: UUID(), title: "A社", day: day, startMinute: 600, endUnset: false, metadata: settings,
                                        isApple: true, appleKey: nil, movedFromLocalID: nil, created: nil, createdAt: Date())])
        let metadataBytes = try Data(contentsOf: metadataURL)
        let journalBytes = try Data(contentsOf: journalURL)
        let apple = FakeAppleCalendar(calendars: [home, work], systemDefaultID: "home",
                                      events: [CalendarEvent(day: day, startMinute: 600, title: "Apple の予定", source: .appleCalendar)])
        let setup = makeConnection(apple: apple, metadata: metadata, journal: journal)

        setup.connection.setAppleLinkEnabled(false)
        let file = JSONFile(url: preferencesURL, empty: CalendarPreferences()).load()
        XCTAssertEqual(file.appleLinkEnabled, false)
        XCTAssertEqual(file.saveTargetKind, .appleCalendar, "保存先の設定は消さない（ON に戻したときに戻す。Q103）")
        XCTAssertEqual(file.defaultCalendarID, "work")
        XCTAssertEqual(file.hiddenCalendarIDs, ["jp"])
        XCTAssertEqual(file.holidayOverrides, ["memo": true])
        XCTAssertEqual(try Data(contentsOf: metadataURL), metadataBytes, "到着目標などの TimyCue の設定を消さない")
        XCTAssertEqual(try Data(contentsOf: journalURL), journalBytes, "保存の途中の記録の Apple の分も、ON に戻すまで残す")
        XCTAssertEqual(apple.storedEvents.count, 1, "Apple 側の予定は削除しない")
        XCTAssertEqual(apple.writes, 0)
    }

    @MainActor
    func testWhileOffNewEventsStayOnThisIPhone() throws {
        try writePreferences(appleDefaultWork())
        let apple = FakeAppleCalendar(calendars: [home, work], systemDefaultID: "home")
        let log = ChangeLog()
        let setup = makeConnection(apple: apple, log: log)
        let localEvent = CalendarEvent(day: day, startMinute: 900, title: "歯医者")
        try setup.local.insert([localEvent])
        setup.connection.setAppleLinkEnabled(false)

        // TimyCueApp と同じつなぎ方：知らせを受けて作成画面に渡す
        let editor = ScheduleEditorStore(repository: setup.switchable, metadataRepository: InMemoryEventMetadataRepository())
        editor.setCalendars(log.rules)
        editor.startNew(on: day)
        editor.content.title = "A社"
        editor.setStartMinute(600)
        try editor.save()
        XCTAssertEqual(apple.writes, 0, "OFF のあいだの新しい予定は Apple へ書かない")
        let saved = try XCTUnwrap(setup.local.allEvents().first(where: { $0.title == "A社" }))
        XCTAssertNil(saved.savedOnDeviceWhileLinked, "連携していないときは印を付けない（ON に戻したあと、既決の条件で重複候補にできる。Q104）")

        try editor.startEditing(eventID: localEvent.id)
        XCTAssertFalse(editor.canMoveToAppleCalendar, "OFF のあいだは「Apple Calendarに保存」を出さない（Q100）")

        let candidate = DuplicateCandidate(local: localEvent,
                                           apple: CalendarEvent(day: day, startMinute: 900, title: "歯医者", source: .appleCalendar))
        XCTAssertNoThrow(try setup.connection.useApple(candidate))
        XCTAssertTrue(setup.local.allEvents().contains { $0.id == localEvent.id }, "OFF のあいだは重複候補の操作もしない")
    }

    // MARK: - ON に戻す

    @MainActor
    func testTurningTheLinkBackOnReusesTheSameRepositoryAndTheRememberedTarget() throws {
        try writePreferences(appleDefaultWork())
        let apple = FakeAppleCalendar(calendars: [home, work], systemDefaultID: "home")
        let log = ChangeLog()
        let created = Counter()
        let setup = makeConnection(apple: apple, log: log, created: created)
        let connection = setup.connection
        XCTAssertEqual(apple.recovers, 1)
        connection.setAppleLinkEnabled(false)
        XCTAssertNil(log.rules)

        XCTAssertTrue(connection.setAppleLinkEnabled(true))
        XCTAssertEqual(created.count, 1, "止めた保存先を使い直す（作り直さない）")
        XCTAssertEqual(apple.resumes, 1)
        XCTAssertEqual(apple.missingResets, 1, "OFF の前に付けた「見つからない」の記録をやり直す（Q103）")
        XCTAssertEqual(apple.recovers, 2, "残しておいた保存の途中の記録を、ON に戻したときに片付ける")
        XCTAssertFalse(setup.switchable.current === setup.local)
        let rules = try XCTUnwrap(log.rules)
        XCTAssertEqual(rules.resolve(choice: nil), .usable(work, source: .settingsDefault), "OFF の前の保存先に戻る（Q103）")
        XCTAssertEqual(connection.preferences.hiddenCalendarIDs, ["jp"], "表示の設定を勝手に ON にしない")
        XCTAssertEqual(connection.statusLabel, "接続済み")
    }

    @MainActor
    func testWhenTurningOffCannotBeSavedTheLinkStaysOn() throws {
        let apple = FakeAppleCalendar(calendars: [home, work], systemDefaultID: "home")
        let setup = makeConnection(apple: apple, preferencesURL: try unwritableURL("calendar-preferences.json"))
        let connection = setup.connection
        XCTAssertTrue(connection.isLinked)

        XCTAssertFalse(connection.setAppleLinkEnabled(false))
        XCTAssertTrue(connection.isLinkEnabled, "保存できなかった変更は戻す（変わったように見せない。spec §89.9）")
        XCTAssertEqual(apple.pauses, 0)
        XCTAssertNotNil(connection.settingsFailure)
        XCTAssertEqual(connection.settingsRevision, 1, "スイッチの見た目も戻す")
        XCTAssertFalse(setup.switchable.current === setup.local)
    }

    @MainActor
    func testDeniedWhileOffShowsNoWarningUntilTurnedOn() throws {
        var preferences = CalendarPreferences()
        preferences.appleLinkEnabled = false
        try writePreferences(preferences)
        let apple = FakeAppleCalendar(calendars: [home], systemDefaultID: "home")
        let created = Counter()
        let connection = makeConnection(apple: apple, authorization: AuthorizationBox(.denied), created: created).connection
        XCTAssertEqual(connection.linkStatus, .off)
        XCTAssertFalse(connection.showsSetupCard, "OFF のあいだに許可が外れても、アクセスの警告を出さない（Q101）")
        XCTAssertEqual(connection.statusLabel, "OFF")

        XCTAssertTrue(connection.setAppleLinkEnabled(true))
        XCTAssertEqual(connection.linkStatus, .needsPermission, "ON に戻そうとしたときに許可を案内する")
        XCTAssertTrue(connection.showsSetupCard)
        XCTAssertEqual(connection.statusLabel, "許可が必要")
        XCTAssertEqual(created.count, 0, "許可がないあいだは Apple カレンダーを使わない")
    }

    @MainActor
    func testPermissionChangesAreFollowedWhenTheAppBecomesActive() throws {
        let apple = FakeAppleCalendar(calendars: [home], systemDefaultID: "home")
        let authorization = AuthorizationBox(.fullAccess)
        let log = ChangeLog()
        let setup = makeConnection(apple: apple, authorization: authorization, log: log)
        XCTAssertTrue(setup.connection.isLinked)

        authorization.status = .denied
        setup.connection.handleBecameActive()
        XCTAssertEqual(apple.pauses, 1, "許可が外れたら Apple カレンダーを止める")
        XCTAssertTrue(setup.switchable.current === setup.local)
        XCTAssertNil(log.rules)
        XCTAssertTrue(setup.connection.showsSetupCard, "連携 ON のまま許可が外れたときは、今の案内のまま（Q115）")

        authorization.status = .fullAccess
        setup.connection.handleBecameActive()
        XCTAssertEqual(apple.resumes, 1, "許可が戻ったら使い直す")
        XCTAssertEqual(apple.missingResets, 1)
        XCTAssertNotNil(log.rules)
    }

    // MARK: - 新しい予定の既定の保存先（設定画面）

    @MainActor
    func testChoosingTheDefaultSaveTargetKeepsTheRememberedCalendar() throws {
        try writePreferences(appleDefaultWork())
        let suiteName = "TimyCueTests.CalendarLinkToggle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let records = SaveTargetRecordStore(defaults: defaults)
        let apple = FakeAppleCalendar(calendars: [home, work], systemDefaultID: "home")
        let connection = makeConnection(apple: apple, records: records).connection

        XCTAssertTrue(connection.setDefaultSaveTarget(.timyCueOnly))
        XCTAssertEqual(connection.preferences.saveTargetKind, .timyCueOnly)
        XCTAssertEqual(connection.preferences.defaultCalendarID, "work", "前に選んでいた Apple カレンダーは覚えておく")
        XCTAssertEqual(records.load(), SaveTargetRecord(kind: .timyCueOnly, calendarID: "work", linkEnabled: nil), "移行の済んだ記録にも写す")

        connection.setDefaultCalendar("home")
        XCTAssertEqual(connection.preferences.saveTargetKind, .appleCalendar)
        XCTAssertEqual(connection.preferences.defaultCalendarID, "home")
        XCTAssertTrue(connection.setDefaultSaveTarget(.systemDefault))
        XCTAssertNil(connection.preferences.defaultCalendarID)
    }

    @MainActor
    func testADefaultSaveTargetThatCannotBeSavedIsReverted() throws {
        let apple = FakeAppleCalendar(calendars: [home, work], systemDefaultID: "home")
        let connection = makeConnection(apple: apple, preferencesURL: try unwritableURL("calendar-preferences.json")).connection
        XCTAssertFalse(connection.setDefaultSaveTarget(.timyCueOnly))
        XCTAssertNil(connection.preferences.saveTargetKind, "保存できなかった変更は戻す")
        XCTAssertNotNil(connection.settingsFailure)
    }

    // MARK: - EventKit の保存先を止める・「見つからない」の記録のやり直し

    func testAPausedEventKitRepositoryWritesNothingAndMissingRecordsCanBeReset() throws {
        let linksURL = directory.appendingPathComponent("eventkit-links.json")
        var links = EventKitLinks()
        let id = UUID()
        links.keys[id] = "item-1"
        links.missingSince = ["item-1": Date(timeIntervalSinceNow: -3600)]
        try JSONEncoder().encode(links).write(to: linksURL)
        let repository = EventKitEventRepository(store: EKEventStore(), metadata: InMemoryEventMetadataRepository(),
                                                 preferences: { CalendarPreferences() }, journal: .inMemory(),
                                                 linksFile: JSONFile(url: linksURL, empty: EventKitLinks()))
        repository.pause()
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社")
        let report = repository.insertEach([event], into: .appleCalendar)
        XCTAssertEqual(report.notSaved.map(\.id), [event.id], "止めているあいだは Apple へ書かない")
        XCTAssertEqual(report.error as? SaveRoutingError, .destinationChanged)
        XCTAssertThrowsError(try repository.update(event)) { error in
            XCTAssertEqual(error as? SaveRoutingError, .destinationChanged)
        }
        XCTAssertTrue(repository.allEvents().isEmpty, "読んだ予定は捨てる（ON に戻したら最新を取り直す）")

        repository.resetMissingRecords()
        let saved = JSONFile(url: linksURL, empty: EventKitLinks()).load()
        XCTAssertNil(saved.missingSince, "「見つからない」の記録をやり直す")
        XCTAssertEqual(saved.keys[id], "item-1", "結び付けは消さない")
    }

    func testAfterTheResetTwoChecksAreNeededAgain() {
        var links = EventKitLinks()
        links.keys = [UUID(): "A", UUID(): "B", UUID(): "C", UUID(): "D"]
        let start = Date()
        _ = links.confirmMissing(["A"], checked: ["A", "B", "C", "D"], now: start, minimumInterval: 300)
        links.resetMissing()
        XCTAssertTrue(links.confirmMissing(["A"], checked: ["A", "B", "C", "D"], now: start.addingTimeInterval(400),
                                           minimumInterval: 300).isEmpty,
                      "OFF の前の記録で済ませず、ON に戻したあと時間をあけた 2 回の確かめが要る（Q103）")
        XCTAssertEqual(links.confirmMissing(["A"], checked: ["A", "B", "C", "D"], now: start.addingTimeInterval(800),
                                            minimumInterval: 300), ["A"])
    }
}

/// iOS のカレンダーの許可の状態（テストで変えられる）
private final class AuthorizationBox {
    var status: EKAuthorizationStatus

    init(_ status: EKAuthorizationStatus) {
        self.status = status
    }
}

/// 作成画面へ渡した知らせ（テスト用）
private final class ChangeLog {
    var count = 0
    var rules: SaveTargetRules?
}

private final class Counter {
    var count = 0
}

/// Apple カレンダーの保存先の代わり（テスト用）。呼ばれた回数を数える
private final class FakeAppleCalendar: AppleCalendarRepository {
    private let base: InMemoryEventRepository
    var onLoaded: (@MainActor () -> Void)?
    var calendarList: [CalendarChoice]
    var systemDefaultCalendarID: String?
    private(set) var calendarReads = 0
    private(set) var reloads = 0
    private(set) var recovers = 0
    private(set) var pauses = 0
    private(set) var resumes = 0
    private(set) var missingResets = 0
    private(set) var writes = 0
    private(set) var isPaused = false

    init(calendars: [CalendarChoice], systemDefaultID: String?, events: [CalendarEvent] = []) {
        base = InMemoryEventRepository(events: events)
        calendarList = calendars
        systemDefaultCalendarID = systemDefaultID
    }

    /// 止めているかによらず、持っている予定（Apple 側の予定が消えていないかを見る）
    var storedEvents: [CalendarEvent] { base.allEvents() }

    func allEvents() -> [CalendarEvent] { isPaused ? [] : base.allEvents() }

    func insert(_ events: [CalendarEvent]) throws {
        writes += events.count
        try base.insert(events)
    }

    func update(_ event: CalendarEvent) throws {
        writes += 1
        try base.update(event)
    }

    func delete(id: UUID) throws {
        writes += 1
        try base.delete(id: id)
    }

    var managesAppleLinks: Bool { true }

    func calendars() -> [CalendarChoice] {
        calendarReads += 1
        return calendarList
    }

    func reloadCache() { reloads += 1 }

    func recover(now: Date) -> [SaveJournalEntry] {
        recovers += 1
        return []
    }

    func pause() {
        pauses += 1
        isPaused = true
    }

    func resume() {
        resumes += 1
        isPaused = false
    }

    func resetMissingRecords() { missingResets += 1 }
}
