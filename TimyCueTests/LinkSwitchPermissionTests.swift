import EventKit
import XCTest
@testable import TimyCue

/// iPhone のカレンダーの許可がなくても、TimyCue の中の「Appleカレンダー連携」を OFF にできる（spec §89.6・2026-10-19 決定
/// 「TestFlight 1.0 (30) 報告への回答」2）。OFF の前に要るものを残す決まりは保つ。ON にすると ON を保存し、まだ許可を求めていなければ
/// 許可を求める。フルアクセスがないあいだは Apple を読み書きしない（EventKit の代わりの保存先で数える）
final class LinkSwitchPermissionTests: XCTestCase {
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green)
    private let work = CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue)
    private var files: AppFiles!

    override func setUpWithError() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        files = AppFiles(folder: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: files.folder)
    }

    /// 連携の設定（保存先は Apple の「仕事」。linkEnabled が nil なら ON）
    private func writePreferences(linkEnabled: Bool?) throws {
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = .appleCalendar
        preferences.defaultCalendarID = "work"
        preferences.hiddenCalendarIDs = ["jp"]
        preferences.appleLinkEnabled = linkEnabled
        preferences.formatVersion = CalendarPreferences.currentFormatVersion
        try JSONEncoder().encode(preferences).write(to: files.preferences)
    }

    /// 前に Apple へ書いたときの結び付けのファイル
    private func writeLinks() throws {
        var links = EventKitLinks()
        let id = UUID()
        links.keys[id] = "item-1"
        links.endUnset = [id]
        try JSONEncoder().encode(links).write(to: files.links)
    }

    private var savedPreferences: CalendarPreferences {
        JSONFile(url: files.preferences, empty: CalendarPreferences()).load()
    }

    private struct Setup {
        let connection: CalendarConnection
        let local: FileEventRepository
        let switchable: SwitchableEventRepository
    }

    /// アプリと同じつなぎ方。Apple カレンダーの保存先は代わりのもの、許可の状態と許可を求める処理はテストで決める
    @MainActor
    private func makeConnection(apple: AppleCalendarStub, permission: PermissionStub, log: LinkNoticeLog = LinkNoticeLog()) -> Setup {
        let local = FileEventRepository(file: JSONFile(url: files.events, empty: []))
        let switchable = SwitchableEventRepository(local)
        let connection = CalendarConnection(eventStore: EKEventStore(), switchable: switchable, localEvents: local,
                                            metadata: InMemoryEventMetadataRepository(),
                                            preferencesFile: JSONFile(url: files.preferences, empty: CalendarPreferences()),
                                            authorizationStatus: { permission.status },
                                            makeAppleRepository: { _, _ in
                                                apple.makeCount += 1
                                                return apple
                                            },
                                            requestAccess: { permission.request() },
                                            onChange: { _, rules, status in log.record(rules, status) })
        return Setup(connection: connection, local: local, switchable: switchable)
    }

    // MARK: - 許可がなくても OFF にできる

    @MainActor
    func testTheLinkCanBeTurnedOffWithoutPermission() throws {
        for status in [EKAuthorizationStatus.notDetermined, .denied, .writeOnly, .restricted] {
            try writePreferences(linkEnabled: nil)
            try writeLinks()
            let linksBytes = files.bytes(files.links)
            let linksModified = files.modified(files.links)
            let apple = AppleCalendarStub(calendars: [home, work], systemDefaultID: "home")
            let log = LinkNoticeLog()
            let setup = makeConnection(apple: apple, permission: PermissionStub(status), log: log)
            let connection = setup.connection
            XCTAssertTrue(connection.isLinkEnabled, "許可 \(status.rawValue)：ON のまま更新した")
            XCTAssertFalse(connection.isLinked)

            XCTAssertTrue(connection.switchAppleLink(false), "許可 \(status.rawValue)：許可がなくても OFF にできる")
            XCTAssertFalse(connection.isLinkEnabled)
            XCTAssertEqual(savedPreferences.appleLinkEnabled, false, "OFF の設定を保存する")
            XCTAssertEqual(savedPreferences.defaultCalendarID, "work", "保存先の設定は消さない（Q103）")
            XCTAssertEqual(connection.linkStatus, .off)
            XCTAssertEqual(connection.statusLabel, status == .restricted ? "利用できません" : "OFF", "設定トップの言い方は今のまま")
            XCTAssertFalse(connection.showsSetupCard, "わざと OFF にしたので、連携を促すカードを出さない（Q102）")
            if status == .restricted {
                XCTAssertNotNil(connection.permissionNote, "端末の制限は OFF でも示す")
            } else {
                XCTAssertNil(connection.permissionNote, "OFF のあいだは許可の案内を出さない（Q101）")
            }
            XCTAssertNil(connection.settingsFailure)
            XCTAssertEqual(apple.makeCount, 0, "許可がないので、Apple カレンダーの保存先を作らない（EventKit を使わない）")
            XCTAssertEqual(apple.calendarReads, 0)
            XCTAssertEqual(apple.writes, 0)
            XCTAssertEqual(files.bytes(files.links), linksBytes, "結び付けのファイルに触れない")
            XCTAssertEqual(files.modified(files.links), linksModified)
            XCTAssertTrue(setup.switchable.current === setup.local, "予定はこの iPhone の中だけ")
            XCTAssertNil(log.rules)
            XCTAssertEqual(log.status, .off, "作成画面へも OFF を知らせる")

            // OFF のまま開き直しても、EventKit を使わない
            let relaunched = makeConnection(apple: apple, permission: PermissionStub(status))
            XCTAssertFalse(relaunched.connection.isLinkEnabled)
            XCTAssertEqual(apple.makeCount, 0)
            XCTAssertEqual(files.bytes(files.links), linksBytes)
        }
    }

    /// 許可が外れて Apple カレンダーの保存先を止めたあと（書けていない結び付けがメモリの上に残っている）も、OFF の前に要るものを残す
    /// 決まりは今のまま。書けなければ OFF にせず、ON のまま理由を出す
    @MainActor
    func testTurningOffWithoutPermissionStillWritesUnsavedLinksFirst() throws {
        try writePreferences(linkEnabled: nil)
        let apple = AppleCalendarStub(calendars: [home, work], systemDefaultID: "home")
        let permission = PermissionStub(.fullAccess)
        let connection = makeConnection(apple: apple, permission: permission).connection
        XCTAssertTrue(connection.isLinked)
        apple.unsavedLinks = true
        apple.linksCanBeSaved = false
        permission.status = .denied
        connection.handleBecameActive()
        XCTAssertEqual(apple.pauses, 1, "許可が外れたので、Apple カレンダーの保存先を止めた")
        XCTAssertFalse(connection.isLinked)

        XCTAssertFalse(connection.switchAppleLink(false), "結び付けを書けなければ、許可がなくても OFF にしない（今の決まりのまま）")
        XCTAssertTrue(connection.isLinkEnabled)
        XCTAssertEqual(connection.settingsFailure?.message, CalendarConnection.linkOffLinksFailureMessage, "理由を出す（文言は仮）")
        XCTAssertEqual(connection.settingsRevision, 1, "スイッチの見た目を ON に戻す")
        XCTAssertNil(savedPreferences.appleLinkEnabled, "OFF の設定を先に書かない")

        connection.dismissSettingsFailure()
        apple.linksCanBeSaved = true
        XCTAssertTrue(connection.switchAppleLink(false))
        XCTAssertFalse(apple.unsavedLinks, "書けていない結び付けを先に書いてから OFF にする")
        XCTAssertEqual(savedPreferences.appleLinkEnabled, false)
        XCTAssertEqual(apple.makeCount, 1, "止めた保存先を使っただけで、作り直さない")
    }

    // MARK: - 許可がないときに ON にする

    @MainActor
    func testTurningTheLinkOnWithoutPermissionSavesItAndAsksOnlyWhenNotYetAsked() async throws {
        for status in [EKAuthorizationStatus.notDetermined, .denied, .writeOnly, .restricted] {
            try writePreferences(linkEnabled: false)
            let apple = AppleCalendarStub(calendars: [home, work], systemDefaultID: "home")
            // 求めたら、拒否された
            let permission = PermissionStub(status, afterRequest: status == .notDetermined ? .denied : nil)
            let log = LinkNoticeLog()
            let setup = makeConnection(apple: apple, permission: permission, log: log)
            let connection = setup.connection

            XCTAssertTrue(connection.switchAppleLink(true), "許可 \(status.rawValue)：TimyCue の設定は ON にできる")
            XCTAssertEqual(savedPreferences.appleLinkEnabled, true, "ON の設定を保存する")
            await connection.permissionRequest?.value
            XCTAssertEqual(permission.requests, status == .notDetermined ? 1 : 0,
                           "許可 \(status.rawValue)：まだ許可を求めていないときだけ求める（拒否・追加のみ・制限は iPhone の設定へ案内する）")
            XCTAssertTrue(connection.isLinkEnabled)
            XCTAssertFalse(connection.isLinked, "フルアクセスがなければ連携していない")
            XCTAssertEqual(apple.makeCount, 0, "Apple カレンダーの保存先を作らない（読みも書きもしない）")
            XCTAssertTrue(setup.switchable.current === setup.local)
            XCTAssertNotNil(connection.permissionNote, "Apple を読み書きしていないことと、許可のしかたを出す")
            XCTAssertNil(log.rules, "作成画面には、連携していないことを渡す")
        }
    }

    @MainActor
    func testTurningTheLinkOnAndAllowingFullAccessStartsTheLink() async throws {
        try writePreferences(linkEnabled: false)
        let apple = AppleCalendarStub(calendars: [home, work], systemDefaultID: "home")
        let permission = PermissionStub(.notDetermined, afterRequest: .fullAccess)
        let log = LinkNoticeLog()
        let connection = makeConnection(apple: apple, permission: permission, log: log).connection

        XCTAssertTrue(connection.switchAppleLink(true))
        await connection.permissionRequest?.value
        XCTAssertEqual(permission.requests, 1)
        XCTAssertTrue(connection.isLinked, "フルアクセスを許可したら連携する")
        XCTAssertEqual(apple.makeCount, 1)
        XCTAssertEqual(apple.missingResets, 1, "連携した直後は「見つからない」の記録をやり直す（今までどおり）")
        XCTAssertEqual(log.status, .linked)
        let rules = try XCTUnwrap(log.rules)
        XCTAssertEqual(rules.resolve(choice: nil), .usable(work, source: .settingsDefault), "OFF の前の保存先に戻る（Q103）")
    }
}
