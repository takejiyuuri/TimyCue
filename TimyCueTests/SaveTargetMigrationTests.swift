import EventKit
import XCTest
@testable import TimyCue

/// 今の利用者の保存先の移行（spec §89.8・Q98・Q111。S2）：一度だけ決める・材料は読むだけ・予定のファイルに触れない・
/// 古い版が書き直したら記録から戻す・材料を開けないときは先送り
final class SaveTargetMigrationTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 19)
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "TimyCueTests.SaveTargetMigration.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private var preferencesURL: URL { directory.appendingPathComponent("calendar-preferences.json") }
    private var records: SaveTargetRecordStore { SaveTargetRecordStore(defaults: defaults) }

    private func savedPreferences(at url: URL? = nil) -> CalendarPreferences {
        JSONFile(url: url ?? preferencesURL, empty: CalendarPreferences()).load()
    }

    private func collect(preferences: CalendarPreferences = CalendarPreferences(), existed: Bool = false) -> SaveTargetMigration.Evidence {
        SaveTargetMigration.collect(folder: directory, preferences: preferences, preferencesFileExisted: existed)
    }

    /// 書けない場所（親がふつうのファイルなので、フォルダを作れない）
    private func unwritableURL(_ name: String) throws -> URL {
        let blocker = directory.appendingPathComponent("blocker-\(name)")
        try Data("x".utf8).write(to: blocker)
        return blocker.appendingPathComponent(name)
    }

    private func writeLocalEvents() throws {
        try JSONEncoder().encode([CalendarEvent(day: day, startMinute: 600, title: "歯医者")])
            .write(to: directory.appendingPathComponent("events.json"))
    }

    /// 終了未設定の印のある結び付け（TimyCue が Apple へ書いたときにしか付かない）
    private func writeLinksWithAppleWrite() throws {
        var links = EventKitLinks()
        let id = UUID()
        links.keys[id] = "item-1"
        links.endUnset = [id]
        try JSONEncoder().encode(links).write(to: directory.appendingPathComponent("eventkit-links.json"))
    }

    private func journalEntry(isApple: Bool, key: String?) -> SaveJournalEntry {
        SaveJournalEntry(id: UUID(), title: "A社", day: day, startMinute: 600, endUnset: false, metadata: nil,
                         isApple: isApple, appleKey: key, movedFromLocalID: nil, created: nil, createdAt: Date())
    }

    @MainActor
    private func makeConnection(preferencesURL url: URL? = nil, live: Bool = true) -> CalendarConnection {
        let local = FileEventRepository(file: JSONFile(url: directory.appendingPathComponent("events.json"), empty: []))
        return CalendarConnection(eventStore: EKEventStore(),
                                  switchable: SwitchableEventRepository(local),
                                  localEvents: live ? local : nil,
                                  metadata: InMemoryEventMetadataRepository(),
                                  preferencesFile: JSONFile(url: url ?? preferencesURL, empty: CalendarPreferences()),
                                  saveTargetRecords: SaveTargetRecordStore(defaults: defaults),
                                  // シミュレータの許可の状態によらないように（移行は許可の状態を材料にしない）
                                  authorizationStatus: { .notDetermined },
                                  onChange: { _, _ in })
    }

    // MARK: - 決め方（Q111 の順）

    func testANewUserStartsWithTimyCueOnly() {
        XCTAssertEqual(SaveTargetMigration.decide(SaveTargetMigration.Evidence()), .decided(.timyCueOnly, reason: .newUser),
                       "使った跡が何もなければ新しい利用者（Q111-3）")
    }

    func testAnExplicitOldChoiceComesFirst() {
        var evidence = SaveTargetMigration.Evidence()
        evidence.explicitCalendarID = "work"
        evidence.usedBefore = true
        evidence.linksCouldNotOpen = true
        XCTAssertEqual(SaveTargetMigration.decide(evidence), .decided(.appleCalendar, reason: .explicitChoice),
                       "はっきり選んだ旧版の保存先をいちばん優先する（開けないファイルがあっても。Q111-1）")
    }

    func testTheOldAutoSwitchNoticeKeepsApple() {
        var evidence = SaveTargetMigration.Evidence()
        evidence.oldAutoSwitchNotice = true
        evidence.usedBefore = true
        XCTAssertEqual(SaveTargetMigration.decide(evidence), .decided(.appleCalendar, reason: .oldAutoSwitch),
                       "旧版の自動の切り替えは Apple に保存していたときだけ起きる（Q111-2）")
    }

    func testAnAppleWriteRecordKeepsApple() {
        var evidence = SaveTargetMigration.Evidence()
        evidence.appleWriteRecord = true
        evidence.usedBefore = true
        XCTAssertEqual(SaveTargetMigration.decide(evidence), .decided(.appleCalendar, reason: .appleWriteRecord))
    }

    func testUsageWithoutAppleEvidenceAsksBeforeSaving() {
        var evidence = SaveTargetMigration.Evidence()
        evidence.usedBefore = true
        XCTAssertEqual(SaveTargetMigration.decide(evidence), .decided(.askBeforeSaving, reason: .unknown),
                       "今の利用者を勝手に TimyCue のみにしない。許可の状態は材料に入れない（Q111-4）")
    }

    func testUnopenableEvidenceDefersTheDecision() {
        var links = SaveTargetMigration.Evidence()
        links.usedBefore = true
        links.linksCouldNotOpen = true
        XCTAssertEqual(SaveTargetMigration.decide(links), .deferred, "書き込みの記録を確かめられないうちは決めない")
        var journal = SaveTargetMigration.Evidence()
        journal.journalCouldNotOpen = true
        XCTAssertEqual(SaveTargetMigration.decide(journal), .deferred)
    }

    func testRestoringAfterAnOldVersionRewroteTheFile() {
        let apple = SaveTargetRecord(kind: .appleCalendar, calendarID: "work", linkEnabled: nil)
        let timyCueOnly = SaveTargetRecord(kind: .timyCueOnly, calendarID: nil, linkEnabled: nil)
        var file = CalendarPreferences()
        file.defaultCalendarID = "work"
        XCTAssertEqual(SaveTargetMigration.restoredKind(record: apple, file: file), .appleCalendar, "保存先が同じなら記録の種類")
        file.defaultCalendarID = "home"
        XCTAssertEqual(SaveTargetMigration.restoredKind(record: apple, file: file), .appleCalendar,
                       "記録が Apple で、別の保存先がはっきりあれば、古い版で選び直したとみなす")
        XCTAssertEqual(SaveTargetMigration.restoredKind(record: timyCueOnly, file: file), .askBeforeSaving,
                       "TimyCue のみから Apple へ黙って入れ替えない")
        file.defaultCalendarID = nil
        XCTAssertEqual(SaveTargetMigration.restoredKind(record: apple, file: file), .askBeforeSaving,
                       "保存先がなくなった（旧版の自動の切り替えと見分けられない）ときは確かめる")
        XCTAssertEqual(SaveTargetMigration.restoredKind(record: timyCueOnly, file: file), .timyCueOnly)
    }

    // MARK: - 材料（読むだけ）

    func testUsageAndAppleWriteRecordsAreRead() throws {
        XCTAssertEqual(collect(), SaveTargetMigration.Evidence(), "空のフォルダは新しい利用者")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Journal", isDirectory: true),
                                                withIntermediateDirectories: true)
        XCTAssertFalse(collect().usedBefore, "保存の途中の記録のフォルダは起動のときに作るので、それだけでは使った跡にしない")
        XCTAssertTrue(collect(existed: true).usedBefore, "起動の時点で設定のファイルがあった")

        try writeLocalEvents()
        let local = collect()
        XCTAssertTrue(local.usedBefore)
        XCTAssertFalse(local.appleWriteRecord, "ローカルの予定だけでは Apple に保存していた証拠にしない")

        try writeLinksWithAppleWrite()
        XCTAssertTrue(collect().appleWriteRecord, "結び付けの終了未設定の印は Apple へ書いたときにしか付かない")

        var preferences = CalendarPreferences()
        preferences.defaultCalendarID = "work"
        preferences.pendingFallbackNotice = true
        let explicit = collect(preferences: preferences)
        XCTAssertEqual(explicit.explicitCalendarID, "work")
        XCTAssertTrue(explicit.oldAutoSwitchNotice)
    }

    func testOnlyAppleWritesInTheJournalCount() throws {
        let folder = directory.appendingPathComponent("Journal", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("save-journal.json")
        try JSONEncoder().encode([journalEntry(isApple: false, key: nil)]).write(to: url)
        let local = collect()
        XCTAssertTrue(local.usedBefore)
        XCTAssertFalse(local.appleWriteRecord, "この iPhone の中への保存の記録は証拠にしない")

        try JSONEncoder().encode([journalEntry(isApple: true, key: nil)]).write(to: url)
        XCTAssertFalse(collect().appleWriteRecord, "Apple へ書き始めていない記録は証拠にしない")

        try JSONEncoder().encode([journalEntry(isApple: true, key: "item-1")]).write(to: url)
        XCTAssertTrue(collect().appleWriteRecord, "Apple に書けた鍵のある記録")
    }

    func testCollectingWritesNothingAndTellsUnopenableFromBroken() throws {
        let linksURL = directory.appendingPathComponent("eventkit-links.json")
        try Data("壊れた中身".utf8).write(to: linksURL)
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let broken = collect()
        XCTAssertTrue(broken.usedBefore, "壊れていても、使った跡にはなる")
        XCTAssertFalse(broken.appleWriteRecord, "壊れた結び付けは書き込みの証拠にしない")
        XCTAssertFalse(broken.linksCouldNotOpen, "壊れているのは、開けないのとは分ける")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), before,
                       "読むだけ（.unreadable- の写しも作らない）")
        XCTAssertEqual(try Data(contentsOf: linksURL), Data("壊れた中身".utf8))

        // 結び付けの場所がフォルダ（あるのに開けない）
        try FileManager.default.removeItem(at: linksURL)
        try FileManager.default.createDirectory(at: linksURL, withIntermediateDirectories: true)
        let unopenable = collect()
        XCTAssertTrue(unopenable.linksCouldNotOpen)
        XCTAssertEqual(SaveTargetMigration.decide(unopenable), .deferred)
    }

    // MARK: - 起動のときの移行（CalendarConnection）

    @MainActor
    func testANewUserIsMigratedToTimyCueOnlyAndItIsRecorded() throws {
        let connection = makeConnection()
        XCTAssertEqual(connection.preferences.saveTargetKind, .timyCueOnly, "本物の保存先では、移行のあと種類が必ず入る")
        let file = savedPreferences()
        XCTAssertEqual(file.saveTargetKind, .timyCueOnly)
        XCTAssertEqual(file.formatVersion, CalendarPreferences.currentFormatVersion)
        XCTAssertEqual(records.load(), SaveTargetRecord(kind: .timyCueOnly, calendarID: nil, linkEnabled: nil),
                       "済んだ記録を UserDefaults に残す")
        XCTAssertNil(connection.settingsFailure)
    }

    @MainActor
    func testTheDecisionIsMadeOnlyOnce() throws {
        _ = makeConnection()
        // そのあと使った跡と Apple への書き込みの印ができても、決め直さない（新しい利用者があとから連携しても変えない。Q98）
        try writeLocalEvents()
        try writeLinksWithAppleWrite()
        XCTAssertEqual(makeConnection().preferences.saveTargetKind, .timyCueOnly)
        XCTAssertEqual(records.load()?.kind, .timyCueOnly)
    }

    @MainActor
    func testAnOldExplicitChoiceBecomesAppleAndTheRestIsKept() throws {
        try Data(#"{"defaultCalendarID":"work","hiddenCalendarIDs":["jp"],"pendingFallbackNotice":true,"holidayOverrides":{"memo":true}}"#.utf8)
            .write(to: preferencesURL)
        let connection = makeConnection()
        XCTAssertEqual(connection.preferences.saveTargetKind, .appleCalendar)
        let file = savedPreferences()
        XCTAssertEqual(file.saveTargetKind, .appleCalendar)
        XCTAssertEqual(file.defaultCalendarID, "work", "はっきり選んだ保存先を保つ")
        XCTAssertEqual(file.pendingFallbackNotice, true, "古い切り替えの印は読むだけで消さない（Q110）")
        XCTAssertEqual(file.hiddenCalendarIDs, ["jp"])
        XCTAssertEqual(file.holidayOverrides, ["memo": true])
        XCTAssertEqual(records.load(), SaveTargetRecord(kind: .appleCalendar, calendarID: "work", linkEnabled: nil))
    }

    @MainActor
    func testMigrationDoesNotTouchEventsSettingsOrLinks() throws {
        try writeLocalEvents()
        var settings = TimyCueEventMetadata()
        settings.arrivalTargetMinutes = 15
        try JSONEncoder().encode([UUID(): settings]).write(to: directory.appendingPathComponent("metadata.json"))
        try writeLinksWithAppleWrite()
        let names = ["events.json", "metadata.json", "eventkit-links.json"]
        let before = try names.map { try Data(contentsOf: directory.appendingPathComponent($0)) }

        let connection = makeConnection()
        XCTAssertEqual(connection.preferences.saveTargetKind, .appleCalendar, "Apple へ書いた印があるので、旧仕様の保存先を引き継ぐ")
        XCTAssertNil(connection.preferences.defaultCalendarID, "iPhone の既定のまま")
        let after = try names.map { try Data(contentsOf: directory.appendingPathComponent($0)) }
        XCTAssertEqual(after, before, "予定・TimyCue の設定・結び付けには何も書かない（複製・移動・削除もしない）")
    }

    @MainActor
    func testWhenTheSettingsCannotBeWrittenTheRecordStillHoldsTheDecision() throws {
        let url = try unwritableURL("calendar-preferences.json")
        let connection = makeConnection(preferencesURL: url)
        XCTAssertEqual(connection.preferences.saveTargetKind, .timyCueOnly, "決めた値はメモリで使う")
        XCTAssertNil(connection.settingsFailure, "利用者の操作ではないので、知らせない")
        XCTAssertEqual(connection.settingsRevision, 0)
        XCTAssertEqual(records.load()?.kind, .timyCueOnly, "記録は先に書く")

        // 次に開いたとき（使った跡が増えていても）、記録から同じ種類に戻る（決め直さない）
        try writeLocalEvents()
        XCTAssertEqual(makeConnection(preferencesURL: url).preferences.saveTargetKind, .timyCueOnly)
    }

    @MainActor
    func testARewriteByAnOldVersionIsRestoredFromTheRecord() throws {
        records.save(SaveTargetRecord(kind: .timyCueOnly, calendarID: nil, linkEnabled: false))
        // 古い版が設定を書き直した（新しい項目が消えた。表示の設定は古い版で変えた）
        try Data(#"{"hiddenCalendarIDs":["jp"]}"#.utf8).write(to: preferencesURL)
        let connection = makeConnection()
        XCTAssertEqual(connection.preferences.saveTargetKind, .timyCueOnly)
        XCTAssertEqual(connection.preferences.appleLinkEnabled, false, "連携の OFF を黙って ON にしない")
        XCTAssertEqual(connection.preferences.hiddenCalendarIDs, ["jp"], "古い版で変えた表示の設定はそのまま")
        let file = savedPreferences()
        XCTAssertEqual(file.saveTargetKind, .timyCueOnly)
        XCTAssertEqual(file.appleLinkEnabled, false)
        XCTAssertEqual(file.formatVersion, CalendarPreferences.currentFormatVersion)

        // 古い版で Apple のカレンダー（家）を選んでいたら、黙って入れ替えず、保存の前に確かめる
        try Data(#"{"defaultCalendarID":"home","hiddenCalendarIDs":[]}"#.utf8).write(to: preferencesURL)
        XCTAssertEqual(makeConnection().preferences.saveTargetKind, .askBeforeSaving)
    }

    @MainActor
    func testUnopenableSettingsDeferTheMigrationWithoutWriting() throws {
        // 設定のファイルの場所にフォルダがある（あるのに開けない）
        try FileManager.default.createDirectory(at: preferencesURL, withIntermediateDirectories: true)
        let connection = makeConnection()
        XCTAssertEqual(connection.preferences.saveTargetKind, .askBeforeSaving, "この起動ではメモリの中だけ「保存の前に確かめる」")
        XCTAssertNil(records.load(), "記録も書かない")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: preferencesURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "開けないファイルを上書きしない")
    }

    @MainActor
    func testWhileDeferredOtherSettingsAreSavedWithoutAProvisionalKind() throws {
        // 結び付けのファイルの場所がフォルダ（開けない）
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("eventkit-links.json"),
                                                withIntermediateDirectories: true)
        let connection = makeConnection()
        XCTAssertEqual(connection.preferences.saveTargetKind, .askBeforeSaving)

        connection.setShown(false, calendarID: "jp")
        let file = savedPreferences()
        XCTAssertEqual(file.hiddenCalendarIDs, ["jp"], "ほかの設定は保存できる")
        XCTAssertNil(file.saveTargetKind, "先送りのあいだは、仮の種類を書かない")
        XCTAssertNil(file.formatVersion)
        XCTAssertNil(records.load())

        // 利用者が保存先をはっきり選んだら、書いて先送りを解く
        connection.setDefaultSaveTarget(.timyCueOnly)
        let chosen = savedPreferences()
        XCTAssertEqual(chosen.saveTargetKind, .timyCueOnly)
        XCTAssertEqual(chosen.formatVersion, CalendarPreferences.currentFormatVersion)
        XCTAssertEqual(records.load()?.kind, .timyCueOnly)
    }

    @MainActor
    func testSampleDataIsNeverMigrated() {
        let connection = makeConnection(live: false)
        XCTAssertNil(connection.preferences.saveTargetKind, "見本の予定では移行しない（前の版と同じ決まりのまま）")
        XCTAssertNil(records.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferencesURL.path), "設定のファイルも作らない")
    }

    // MARK: - ファイルの形（spec §89.8：なくても読める項目を足すだけ）

    func testUnknownKindsAndOldFilesStillLoad() throws {
        let future = try JSONDecoder().decode(CalendarPreferences.self,
                                              from: Data(#"{"hiddenCalendarIDs":[],"saveTargetKind":"somethingNew","formatVersion":3}"#.utf8))
        XCTAssertEqual(future.saveTargetKind, .askBeforeSaving, "先の版の知らない値でも、ファイル全体を読めなくしない")
        XCTAssertEqual(future.formatVersion, 3)

        let old = try JSONDecoder().decode(CalendarPreferences.self, from: Data(#"{"hiddenCalendarIDs":["jp"]}"#.utf8))
        XCTAssertNil(old.saveTargetKind)
        XCTAssertNil(old.appleLinkEnabled)
        XCTAssertTrue(old.isAppleLinkEnabled, "古い設定は連携 ON")
        XCTAssertNil(old.formatVersion)

        var value = CalendarPreferences()
        value.saveTargetKind = .timyCueOnly
        value.appleLinkEnabled = false
        value.formatVersion = CalendarPreferences.currentFormatVersion
        XCTAssertEqual(try JSONDecoder().decode(CalendarPreferences.self, from: JSONEncoder().encode(value)), value)
    }
}
