import EventKit
import XCTest
@testable import TimyCue

/// 起動のときに連携の設定（設定のファイル）を開けないとき（spec §89.6・2026-10-19 決定「TestFlight 1.0 (30) 報告への回答」3）：
/// 連携の ON/OFF を確かめられない状態にして（ON とも OFF とも、許可なしとも別）、Apple カレンダーを読み書きせず、設定のファイルに書かず、
/// 移行もせず、結び付け・TimyCue の設定・保存の途中の記録・予定を消さない。読めるようになったら読み直して、その設定に従う。
/// 作成画面は、新しい予定を黙って TimyCue のみにせず、保存の前に確かめる。
/// 「開けない」は、設定のファイルの場所にフォルダを置いて作る（端末のロック中に開けないときの代わり）
final class LinkSettingUnconfirmedTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 19)
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green)
    private let work = CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue)
    private var files: AppFiles!
    private var suiteName: String!
    private var defaults: UserDefaults!

    /// TestFlight 1.0 (30) が書く形の設定（連携 ON・保存先は Apple の「仕事」）
    private let linkedSettingsJSON = #"{"defaultCalendarID":"work","hiddenCalendarIDs":["jp"],"saveTargetKind":"appleCalendar","formatVersion":2}"#
    /// TestFlight 1.0 (30) が書く形の設定（連携 OFF・保存先は TimyCue のみ）
    private let offSettingsJSON = #"{"hiddenCalendarIDs":[],"saveTargetKind":"timyCueOnly","appleLinkEnabled":false,"formatVersion":2}"#

    override func setUpWithError() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        files = AppFiles(folder: folder)
        suiteName = "TimyCueTests.LinkSettingUnconfirmed.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: files.folder)
    }

    /// 移行の済んだ記録（テスト用の UserDefaults）
    private var records: SaveTargetRecordStore { SaveTargetRecordStore(defaults: defaults) }

    private struct Setup {
        let connection: CalendarConnection
        let local: FileEventRepository
        let switchable: SwitchableEventRepository
        let editor: ScheduleEditorStore
    }

    /// アプリと同じつなぎ方で起動する（作成画面へ知らせを渡す。移行の済んだ記録を使う本物の保存先と同じ形）
    @MainActor
    private func launch(apple: AppleCalendarStub, permission: PermissionStub = PermissionStub(.fullAccess),
                        log: LinkNoticeLog = LinkNoticeLog(),
                        metadata: EventMetadataRepository = InMemoryEventMetadataRepository(),
                        journal: SaveJournal = .inMemory()) -> Setup {
        let local = FileEventRepository(file: JSONFile(url: files.events, empty: []))
        let switchable = SwitchableEventRepository(local)
        let editor = ScheduleEditorStore(repository: switchable, metadataRepository: InMemoryEventMetadataRepository())
        let connection = CalendarConnection(eventStore: EKEventStore(), switchable: switchable, localEvents: local,
                                            metadata: metadata,
                                            preferencesFile: JSONFile(url: files.preferences, empty: CalendarPreferences()),
                                            journal: journal,
                                            saveTargetRecords: records,
                                            authorizationStatus: { permission.status },
                                            makeAppleRepository: { _, _ in
                                                apple.makeCount += 1
                                                return apple
                                            },
                                            requestAccess: { permission.request() },
                                            onChange: { _, rules, status in
                                                log.record(rules, status)
                                                editor.refresh()
                                                editor.receiveLink(rules, status: status)
                                            })
        return Setup(connection: connection, local: local, switchable: switchable, editor: editor)
    }

    // MARK: - 確かめられないあいだ

    @MainActor
    func testUnreadableSettingsStopAppleAccessAndWriteNothing() throws {
        try files.makePreferencesUnopenable()
        // 予定・TimyCue の設定・結び付け・この iPhone の中への保存の途中の記録
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        try JSONEncoder().encode([localEvent]).write(to: files.events)
        var settings = TimyCueEventMetadata()
        settings.arrivalTargetMinutes = 15
        try JSONEncoder().encode([localEvent.id: settings]).write(to: files.metadata)
        var links = EventKitLinks()
        let linkedID = UUID()
        links.keys[linkedID] = "item-1"
        links.endUnset = [linkedID]
        try JSONEncoder().encode(links).write(to: files.links)
        SaveJournal(file: JSONFile(url: files.journal, empty: [])).begin([
            SaveJournalEntry(id: localEvent.id, title: "歯医者", day: day, startMinute: 600, endUnset: false, metadata: settings,
                             isApple: false, appleKey: nil, movedFromLocalID: nil, created: true, createdAt: Date()),
        ])
        let watched = [files.events, files.metadata, files.links, files.journal]
        let before = watched.map { files.bytes($0) }

        let apple = AppleCalendarStub(calendars: [home, work], systemDefaultID: "home")
        let log = LinkNoticeLog()
        let setup = launch(apple: apple, log: log,
                           metadata: FileEventMetadataRepository(file: JSONFile(url: files.metadata, empty: [:])),
                           journal: SaveJournal(file: JSONFile(url: files.journal, empty: [])))
        let connection = setup.connection

        XCTAssertTrue(connection.isLinkSettingUnconfirmed)
        XCTAssertEqual(connection.linkStatus, .unconfirmed, "ON とも OFF とも、許可なしとも別の状態")
        XCTAssertFalse(connection.isLinked, "フルアクセスがあっても、連携していないとして扱う")
        XCTAssertTrue(connection.hasFullAccess, "iPhone の許可は別の状態のまま")
        XCTAssertEqual(connection.statusLabel, "確認中", "設定トップの状態（文言は仮）")
        XCTAssertEqual(connection.permissionStateLabel, "許可あり")
        XCTAssertNil(connection.permissionNote, "ON とは言えないので、ON のときの許可の説明は出さない")
        XCTAssertFalse(connection.showsSetupCard, "Home の連携を促すカードを出さない（未連携の案内と混同しない）")
        XCTAssertFalse(connection.showsDuplicateNotice, "重複の案内も出さない")
        XCTAssertFalse(connection.showsFirstGuidance)
        XCTAssertEqual(apple.makeCount, 0, "EventKit の保存先を作らない")
        XCTAssertEqual(apple.calendarReads, 0, "カレンダーも予定も読まない")
        XCTAssertTrue(setup.switchable.current === setup.local, "この iPhone の中の予定は、読み込める範囲で使えるまま")
        XCTAssertEqual(setup.local.allEvents().map(\.id), [localEvent.id])
        XCTAssertEqual(log.status, .unconfirmed, "作成画面へ、確かめられないことを知らせる")
        XCTAssertNil(log.rules)
        XCTAssertNil(records.load(), "移行もしない（記録を書かない）")

        // 前面に戻っても・Apple 側が変わっても、読めないままなら触れない。設定を変えようとしても書かない
        connection.handleBecameActive()
        connection.calendarDidChange()
        XCTAssertFalse(connection.setAppleLinkEnabled(false), "確かめられないあいだは、連携を変えない")
        XCTAssertEqual(connection.settingsFailure?.message, CalendarConnection.unconfirmedSettingsFailureMessage, "理由を出す（文言は仮）")
        XCTAssertFalse(connection.switchAppleLink(true))
        XCTAssertFalse(connection.setDefaultSaveTarget(.timyCueOnly))
        XCTAssertFalse(connection.setShown(false, calendarID: "home"))
        XCTAssertTrue(connection.isLinkSettingUnconfirmed)
        XCTAssertEqual(apple.makeCount, 0)
        XCTAssertTrue(files.preferencesStillUnopenable, "設定のファイルを書かない（空の設定で上書きしない）")
        XCTAssertNil(records.load())
        XCTAssertEqual(watched.map { files.bytes($0) }, before,
                       "予定・TimyCue の設定・結び付け・保存の途中の記録を消さない・やり直さない")
    }

    func testTheUnconfirmedStateIsShownApartFromOnOffAndPermission() {
        for authorization in [EKAuthorizationStatus.fullAccess, .notDetermined, .denied, .writeOnly, .restricted] {
            XCTAssertEqual(AppleLinkStatus.unconfirmed.statusLabel(authorization: authorization), "確認中",
                           "許可 \(authorization.rawValue)：許可の状態によらず「確認中」（文言は仮）")
        }
        XCTAssertFalse(AppleLinkStatus.unconfirmed.showsSetupCard, "連携を促すカードを出さない")
        XCTAssertEqual(AppleLinkStatus.unconfirmed.saveUnavailableReason, "連携の設定を確かめられません")
        for enabled in [true, false] {
            for authorization in [EKAuthorizationStatus.fullAccess, .notDetermined, .denied, .writeOnly, .restricted] {
                XCTAssertNotEqual(AppleLinkStatus.resolve(authorization: authorization, linkEnabled: enabled), .unconfirmed,
                                  "読めた設定から決める状態は、確かめられない状態にならない")
            }
        }
    }

    // MARK: - 読み直し

    @MainActor
    func testReadableSettingsAreFollowedAfterReloading() throws {
        try files.makePreferencesUnopenable()
        let apple = AppleCalendarStub(calendars: [home, work], systemDefaultID: "home")
        let log = LinkNoticeLog()
        let setup = launch(apple: apple, log: log)
        let connection = setup.connection

        XCTAssertFalse(connection.reloadPreferences(), "まだ読めない")
        XCTAssertFalse(connection.preferencesStillUnreadable, "自動の読み直しでは、読めなかったことを出さない")
        connection.retryReadingPreferences()
        XCTAssertTrue(connection.preferencesStillUnreadable, "「もう一度読み込む」で読めなかったことを出す")
        XCTAssertTrue(connection.isLinkSettingUnconfirmed)
        XCTAssertEqual(apple.makeCount, 0)

        // ロックを解除して読めるようになった（1.0 (30) が書いた形のまま）。アプリが前面に戻ったときに読み直す
        try files.makePreferencesReadable(linkedSettingsJSON)
        let bytes = files.bytes(files.preferences)
        let modified = files.modified(files.preferences)
        connection.handleBecameActive()
        XCTAssertFalse(connection.isLinkSettingUnconfirmed)
        XCTAssertFalse(connection.preferencesStillUnreadable)
        XCTAssertEqual(connection.linkStatus, .linked)
        XCTAssertTrue(connection.isLinked)
        XCTAssertEqual(apple.makeCount, 1, "連携 ON でフルアクセスがあれば、EventKit を使い始める")
        XCTAssertEqual(apple.missingResets, 0, "起動のときと同じく、「見つからない」の記録はやり直さない")
        XCTAssertFalse(setup.switchable.current === setup.local)
        let rules = try XCTUnwrap(log.rules, "作成画面へ知らせる")
        XCTAssertEqual(log.status, .linked)
        XCTAssertEqual(rules.resolve(choice: nil), .usable(work, source: .settingsDefault), "読めた設定のとおり")
        XCTAssertEqual(connection.preferences.hiddenCalendarIDs, ["jp"])
        XCTAssertEqual(connection.statusLabel, "接続済み")
        XCTAssertEqual(files.bytes(files.preferences), bytes, "新しい版が書いた設定は、書き直さない")
        XCTAssertEqual(files.modified(files.preferences), modified)
        XCTAssertEqual(records.load(), SaveTargetRecord(kind: .appleCalendar, calendarID: "work", linkEnabled: nil),
                       "移行の済んだ記録を、読めた設定から写す")
    }

    @MainActor
    func testReadableOffSettingsKeepAppleCalendarUntouched() throws {
        try files.makePreferencesUnopenable()
        let apple = AppleCalendarStub(calendars: [home, work], systemDefaultID: "home")
        let log = LinkNoticeLog()
        let connection = launch(apple: apple, log: log).connection

        // ロックを解除して読めるようになった（protectedDataDidBecomeAvailable と同じ呼び方）
        try files.makePreferencesReadable(offSettingsJSON)
        XCTAssertTrue(connection.reloadPreferences())
        XCTAssertEqual(connection.linkStatus, .off)
        XCTAssertFalse(connection.isLinked)
        XCTAssertEqual(apple.makeCount, 0, "OFF なら EventKit を使わない")
        XCTAssertEqual(apple.calendarReads, 0)
        XCTAssertEqual(log.status, .off)
        XCTAssertNil(log.rules)
        XCTAssertEqual(connection.statusLabel, "OFF")
        XCTAssertFalse(connection.showsSetupCard)
        XCTAssertTrue(connection.reloadPreferences(), "確かめられたあとは、何もしない")
        XCTAssertEqual(apple.makeCount, 0)
    }

    @MainActor
    func testTheDeferredMigrationRunsAfterReloading() throws {
        try files.makePreferencesUnopenable()
        let apple = AppleCalendarStub(calendars: [home, work], systemDefaultID: "home")
        let connection = launch(apple: apple).connection
        XCTAssertNil(records.load())

        // 前の版が書いた形（保存先の種類と版の印がない。はっきり選んだ保存先がある）
        try files.makePreferencesReadable(#"{"defaultCalendarID":"work","hiddenCalendarIDs":[]}"#)
        XCTAssertTrue(connection.reloadPreferences())
        XCTAssertEqual(connection.preferences.saveTargetKind, .appleCalendar, "先送りしていた移行を、ここで行う（はっきり選んだ保存先を引き継ぐ）")
        XCTAssertEqual(connection.preferences.defaultCalendarID, "work")
        XCTAssertEqual(records.load(), SaveTargetRecord(kind: .appleCalendar, calendarID: "work", linkEnabled: nil))
        let file = JSONFile(url: files.preferences, empty: CalendarPreferences()).load()
        XCTAssertEqual(file.saveTargetKind, .appleCalendar)
        XCTAssertEqual(file.formatVersion, CalendarPreferences.currentFormatVersion)
        XCTAssertTrue(connection.isLinked)
        XCTAssertEqual(apple.makeCount, 1)
    }

    // MARK: - 作成画面

    @MainActor
    func testTheEditorAsksBeforeSavingWhileUnconfirmed() throws {
        try files.makePreferencesUnopenable()
        let apple = AppleCalendarStub(calendars: [home, work], systemDefaultID: "home")
        let setup = launch(apple: apple)
        let editor = setup.editor
        editor.startNew(on: day)
        XCTAssertTrue(editor.showsCalendarRow, "実際の保存先が見えるように行を出す")
        XCTAssertEqual(editor.calendarRowValues, ["確認中（保存するときに確かめます）", "確認中"], "黙って TimyCue のみと出さない（文言は仮）")
        XCTAssertNil(editor.linkLossPrompt, "足りない項目があるときは、先に行で知らせる（§46）")

        editor.content.title = "A社"
        editor.setStartMinute(600)
        XCTAssertEqual(editor.linkLossPrompt,
                       "Apple カレンダーの設定を確かめられないため、Apple カレンダーには保存できません。TimyCue のみ（このiPhone）に保存しますか？")
        XCTAssertFalse(editor.isLocked(.calendar), "行で TimyCue のみを選べる")
        XCTAssertEqual(editor.calendarRowChoices, [.timyCueOnly])
        XCTAssertTrue(editor.calendarRowNote?.hasPrefix("Apple カレンダーの設定を確かめられないため") ?? false)
        XCTAssertFalse(editor.needsFirstSaveTargetChoice)
        XCTAssertNil(editor.saveTargetPrompt)
        XCTAssertNil(editor.saveTargetChangePrompt)
        XCTAssertThrowsError(try editor.save(), "確かめずには保存しない（最後の守り）") { error in
            XCTAssertEqual(error as? ScheduleEditorError, .needsLinkLossConfirmation)
        }
        XCTAssertTrue(setup.local.allEvents().isEmpty)
        XCTAssertEqual(apple.writes, 0)

        // ［TimyCue のみ（このiPhone）に保存］：はっきり選んでから保存する
        editor.chooseSaveTarget(.timyCueOnly)
        XCTAssertNil(editor.linkLossPrompt)
        XCTAssertEqual(editor.calendarRowValue, "TimyCue のみ（このiPhone）")
        XCTAssertTrue(editor.isLocked(.calendar), "ほかに選べるものはない")
        try editor.save()
        XCTAssertEqual(setup.local.allEvents().map(\.title), ["A社"])
        XCTAssertNil(setup.local.allEvents().first?.savedOnDeviceWhileLinked, "連携していないときの保存なので、印は付けない（Q104）")
        XCTAssertEqual(apple.writes, 0)
        XCTAssertTrue(files.preferencesStillUnopenable)
    }

    /// 確かめられないあいだに開いた作成画面で、設定を読めて連携したとき：確かめられないあいだに Apple の保存先は出していないので、
    /// 開いているあいだに連携したときと同じく、黙って Apple へ変えず TimyCue のみのまま行に出す（行で Apple を選び直せる）
    @MainActor
    func testAnEditorOpenedWhileUnconfirmedStaysTimyCueOnlyWhenTheLinkIsConfirmed() throws {
        try files.makePreferencesUnopenable()
        let apple = AppleCalendarStub(calendars: [home, work], systemDefaultID: "home")
        let setup = launch(apple: apple)
        let editor = setup.editor
        editor.startNew(on: day)
        editor.content.title = "A社"
        editor.setStartMinute(600)
        XCTAssertNotNil(editor.linkLossPrompt)

        try files.makePreferencesReadable(linkedSettingsJSON)
        XCTAssertTrue(setup.connection.reloadPreferences())
        XCTAssertTrue(editor.isConnectedToApple)
        XCTAssertNil(editor.linkLossPrompt)
        XCTAssertEqual(editor.content.saveChoice, .timyCueOnly)
        XCTAssertTrue(editor.showsCalendarRow)
        XCTAssertEqual(editor.calendarRowValue, "TimyCue のみ（このiPhone）")
        XCTAssertFalse(editor.isLocked(.calendar), "行で Apple カレンダーを選び直せる")
        XCTAssertNil(editor.saveTargetChangePrompt)
        try editor.save()
        XCTAssertEqual(apple.writes, 0, "Apple へは書かない")
        XCTAssertEqual(setup.local.allEvents().first?.savedOnDeviceWhileLinked, true, "連携中に TimyCue のみで保存した印（Q104）")
    }
}
