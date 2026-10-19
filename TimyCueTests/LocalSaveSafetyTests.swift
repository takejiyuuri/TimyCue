import EventKit
import XCTest
@testable import TimyCue

/// 端末の中の保存と設定の保存の安全（spec §89.9・2026-10-18 S1b 指示 6・8）：
/// 書けてからメモリを変える・押し直しで重複しない・読めないファイルを空として上書きしない・設定の保存の失敗で値を戻して知らせる
final class LocalSaveSafetyTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 18)
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 書けない場所（親がふつうのファイルなので、フォルダを作れない）
    private func unwritableURL(_ name: String) throws -> URL {
        let blocker = directory.appendingPathComponent("blocker-\(name)")
        try Data("x".utf8).write(to: blocker)
        return blocker.appendingPathComponent(name)
    }

    // MARK: - 予定のファイル

    func testEventsStayUnchangedWhenTheFileCannotBeWritten() throws {
        let existing = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let repository = FileEventRepository(file: JSONFile(url: try unwritableURL("events.json"), empty: []))
        XCTAssertTrue(repository.allEvents().isEmpty)

        XCTAssertThrowsError(try repository.insert([existing]))
        XCTAssertTrue(repository.allEvents().isEmpty, "書けなかったら、メモリの上でも保存したことにしない")
    }

    func testUpdateAndDeleteKeepTheEventWhenWritingFails() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let url = directory.appendingPathComponent("events.json")
        let file = JSONFile<[CalendarEvent]>(url: url, empty: [])
        try file.save([event])
        let repository = FileEventRepository(file: file)
        // 書けなくする（フォルダをふつうのファイルに置き換えるのではなく、ファイルの場所をフォルダにする）
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        var edited = event
        edited.title = "歯医者（変更）"
        XCTAssertThrowsError(try repository.update(edited))
        XCTAssertEqual(repository.allEvents().first?.title, "歯医者", "書けなかった変更はメモリにも入れない")
        XCTAssertThrowsError(try repository.delete(id: event.id))
        XCTAssertEqual(repository.allEvents().map(\.id), [event.id], "消せなかった予定はそのまま（再起動で戻ることもない）")
    }

    func testInsertingTheSameEventAgainDoesNotDuplicate() throws {
        let repository = FileEventRepository(file: JSONFile(url: directory.appendingPathComponent("events.json"), empty: []))
        let event = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        try repository.insert([event])
        try repository.insert([event])
        XCTAssertEqual(repository.allEvents().count, 1, "押し直しで同じ予定を重複させない")
        let reloaded = FileEventRepository(file: JSONFile(url: directory.appendingPathComponent("events.json"), empty: []))
        XCTAssertEqual(reloaded.allEvents().map(\.id), [event.id], "ファイルにも 1 件だけ")
    }

    // MARK: - TimyCue の設定のファイル

    func testMetadataStaysUnchangedWhenTheFileCannotBeWritten() throws {
        let repository = FileEventMetadataRepository(file: JSONFile(url: try unwritableURL("metadata.json"), empty: [:]))
        var settings = TimyCueEventMetadata()
        settings.arrivalTargetMinutes = 15
        let id = UUID()
        XCTAssertThrowsError(try repository.save(settings, for: id))
        XCTAssertNil(repository.allMetadata()[id])
        XCTAssertThrowsError(try repository.saveAll([id: settings]))
        XCTAssertTrue(repository.allMetadata().isEmpty)
    }

    // MARK: - 読めないファイル

    func testAnUnreadableFileIsKeptUnderAnotherNameBeforeStartingEmpty() throws {
        let url = directory.appendingPathComponent("events.json")
        try Data("壊れた中身".utf8).write(to: url)
        let file = JSONFile<[CalendarEvent]>(url: url, empty: [])
        let repository = FileEventRepository(file: file)
        XCTAssertTrue(repository.allEvents().isEmpty, "壊れていてもアプリ全体は止めない（§80）")
        let backup = try XCTUnwrap(file.unreadableBackup, "空として上書きする前に、別名で残す")
        XCTAssertEqual(try Data(contentsOf: backup), Data("壊れた中身".utf8))

        try repository.insert([CalendarEvent(day: day, startMinute: 600, title: "新しい予定")])
        XCTAssertEqual(try Data(contentsOf: backup), Data("壊れた中身".utf8), "残したファイルは消えない")
    }

    /// 写しの数（「events.json.unreadable-…」）
    private func backups(of name: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(name + ".unreadable-") }
    }

    func testAnUnreadableFileIsKeptOnlyOnceAcrossLaunches() throws {
        let url = directory.appendingPathComponent("events.json")
        try Data("壊れた中身".utf8).write(to: url)
        let first = JSONFile<[CalendarEvent]>(url: url, empty: [])
        _ = FileEventRepository(file: first)
        // 保存しないまま、もう一度起動した
        let second = JSONFile<[CalendarEvent]>(url: url, empty: [])
        _ = FileEventRepository(file: second)
        let third = JSONFile<[CalendarEvent]>(url: url, empty: [])
        _ = FileEventRepository(file: third)

        XCTAssertEqual(try backups(of: "events.json").count, 1, "同じ壊れた中身では、起動のたびに写しを増やさない")
        XCTAssertEqual(second.unreadableBackup, first.unreadableBackup, "最初の写しを使う")
        XCTAssertEqual(third.unreadableBackup, first.unreadableBackup)
        XCTAssertEqual(try Data(contentsOf: url), Data("壊れた中身".utf8), "原本は消さない")
    }

    func testNewUnreadableContentGetsAnotherCopyAndTheFirstIsKept() throws {
        let url = directory.appendingPathComponent("events.json")
        try Data("壊れた中身 1".utf8).write(to: url)
        let first = JSONFile<[CalendarEvent]>(url: url, empty: [])
        _ = first.load()
        let firstBackup = try XCTUnwrap(first.unreadableBackup)

        try Data("壊れた中身 2".utf8).write(to: url)
        let second = JSONFile<[CalendarEvent]>(url: url, empty: [])
        _ = second.load()
        let secondBackup = try XCTUnwrap(second.unreadableBackup)

        XCTAssertNotEqual(firstBackup, secondBackup, "違う壊れた中身は、別の写しに残す（同じ秒でも上書きしない）")
        XCTAssertEqual(try Data(contentsOf: firstBackup), Data("壊れた中身 1".utf8), "前の写しは消さない")
        XCTAssertEqual(try Data(contentsOf: secondBackup), Data("壊れた中身 2".utf8))
        XCTAssertEqual(try backups(of: "events.json").count, 2)
    }

    func testAFileThatCannotBeOpenedIsNotOverwritten() throws {
        // ファイルの場所にフォルダがある（あるのに開けない）
        let url = directory.appendingPathComponent("events.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = JSONFile<[CalendarEvent]>(url: url, empty: [])
        let repository = FileEventRepository(file: file)
        XCTAssertTrue(file.couldNotOpen)
        XCTAssertNil(file.unreadableBackup, "一時的に開けないのは、壊れているのとは分ける（写しを作らない）")
        XCTAssertTrue(try backups(of: "events.json").isEmpty)
        XCTAssertThrowsError(try repository.insert([CalendarEvent(day: day, startMinute: 600, title: "A社")])) { error in
            XCTAssertEqual(error as? JSONFileError, .couldNotOpen(url), "開けなかったファイルを空の中身で上書きしない")
        }
    }

    // MARK: - カレンダー連携の設定（spec §89.9）

    @MainActor
    private func makeConnection(preferencesURL: URL, metadata: EventMetadataRepository = InMemoryEventMetadataRepository(),
                                localEvents: FileEventRepository? = nil) -> CalendarConnection {
        let local = localEvents ?? FileEventRepository(file: JSONFile(url: directory.appendingPathComponent("local.json"), empty: []))
        return CalendarConnection(eventStore: EKEventStore(),
                                  switchable: SwitchableEventRepository(local),
                                  localEvents: local,
                                  metadata: metadata,
                                  preferencesFile: JSONFile(url: preferencesURL, empty: CalendarPreferences()),
                                  onChange: { _, _, _ in })
    }

    @MainActor
    func testSettingsAreRevertedAndReportedWhenTheyCannotBeSaved() throws {
        let connection = makeConnection(preferencesURL: try unwritableURL("prefs.json"))
        connection.setDefaultCalendar("work")
        XCTAssertNil(connection.preferences.defaultCalendarID, "保存できなかった変更は戻す（変更済みと誤って見せない）")
        XCTAssertNotNil(connection.settingsFailure, "保存できなかったことを知らせる")

        connection.dismissSettingsFailure()
        XCTAssertNil(connection.settingsFailure)
        connection.setShown(false, calendarID: "jp")
        XCTAssertTrue(connection.preferences.isShown("jp"), "表示の切り替えも戻す")
        XCTAssertNotNil(connection.settingsFailure)
    }

    @MainActor
    func testEachSettingsFailureIsReportedAgainAndRedrawsTheRows() throws {
        let connection = makeConnection(preferencesURL: try unwritableURL("prefs.json"))
        connection.setDefaultCalendar("work")
        let first = try XCTUnwrap(connection.settingsFailure)
        let revision = connection.settingsRevision
        connection.setHoliday(true, calendar: CalendarChoice(id: "jp", title: "日本の祝日", sourceTitle: "購読", isWritable: false, color: .green))
        let second = try XCTUnwrap(connection.settingsFailure)
        XCTAssertNotEqual(first.id, second.id, "続けて失敗しても、そのたびに知らせる")
        XCTAssertGreaterThan(connection.settingsRevision, revision, "戻した値でスイッチや選択の行を描き直す")
    }

    @MainActor
    func testBookkeepingIsRevertedWithoutAnAlert() throws {
        let connection = makeConnection(preferencesURL: try unwritableURL("prefs.json"))
        connection.dismissGuidance()
        XCTAssertNil(connection.preferences.guidanceDismissCount, "案内を「あとで」にした回数も、保存できなければ戻す")
        connection.markDuplicatesNotified()
        XCTAssertNil(connection.preferences.notifiedDuplicates)
        XCTAssertNil(connection.settingsFailure, "案内を閉じた印は、保存できなくても知らせない（予定の保存の途中に混ぜて見せない）")
    }

    @MainActor
    func testSettingsAreKeptWhenSaved() throws {
        let url = directory.appendingPathComponent("prefs.json")
        let connection = makeConnection(preferencesURL: url)
        connection.setDefaultCalendar("work")
        XCTAssertEqual(connection.preferences.defaultCalendarID, "work")
        XCTAssertNil(connection.settingsFailure)
        XCTAssertEqual(JSONFile(url: url, empty: CalendarPreferences()).load().defaultCalendarID, "work")
    }

    // MARK: - 重複候補の「Apple Calendarの予定を使う」（spec §89.9）

    @MainActor
    func testUseAppleKeepsBothWhenTheSettingsCannotBeCopied() throws {
        let local = FileEventRepository(file: JSONFile(url: directory.appendingPathComponent("local.json"), empty: []))
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        try local.insert([localEvent])
        let apple = CalendarEvent(day: day, startMinute: 600, title: "歯医者", source: .appleCalendar, calendarID: "home")
        let metadata = FileEventMetadataRepository(file: JSONFile(url: try unwritableURL("metadata.json"), empty: [:]))
        let connection = makeConnection(preferencesURL: directory.appendingPathComponent("prefs.json"), metadata: metadata, localEvents: local)

        XCTAssertThrowsError(try connection.useApple(DuplicateCandidate(local: localEvent, apple: apple)))
        XCTAssertEqual(local.allEvents().map(\.id), [localEvent.id], "設定を引き継げなかったら、TimyCue の予定は消さない")
    }

    @MainActor
    func testUseAppleIsDoneWhenTheLocalEventIsAlreadyGone() throws {
        let local = FileEventRepository(file: JSONFile(url: directory.appendingPathComponent("local.json"), empty: []))
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let apple = CalendarEvent(day: day, startMinute: 600, title: "歯医者", source: .appleCalendar, calendarID: "home")
        let connection = makeConnection(preferencesURL: directory.appendingPathComponent("prefs.json"), localEvents: local)
        XCTAssertNoThrow(try connection.useApple(DuplicateCandidate(local: localEvent, apple: apple)),
                         "前の操作でもう消えていれば、済んでいる（押し直しでずっと失敗しない）")
    }
}
