import EventKit
import XCTest
@testable import TimyCue

/// 保存の途中でアプリが終わったときの記録と、次に開いたときの復旧（spec §89.9・2026-10-18 S1b 指示 5・6）
final class SaveJournalTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 19)
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func journalFile() -> JSONFile<[SaveJournalEntry]> {
        JSONFile(url: directory.appendingPathComponent("save-journal.json"), empty: [])
    }

    private func entry(_ id: UUID = UUID(), key: String? = nil, isApple: Bool = true, movedFrom: UUID? = nil,
                       arrival: Int = 15) -> SaveJournalEntry {
        var settings = TimyCueEventMetadata()
        settings.arrivalTargetMinutes = arrival
        return SaveJournalEntry(id: id, title: "A社", day: day, startMinute: 600, endUnset: false, metadata: settings,
                                isApple: isApple, appleKey: key, movedFromLocalID: movedFrom, created: nil, createdAt: Date())
    }

    // MARK: - 記録

    func testJournalSurvivesRestart() throws {
        let id = UUID()
        let journal = SaveJournal(file: journalFile())
        journal.begin([entry(id)])
        journal.recordKey("item-1", for: id)

        let reopened = SaveJournal(file: journalFile())
        XCTAssertEqual(reopened.entries.map(\.id), [id], "アプリが終わっても、記録は残る")
        XCTAssertEqual(reopened.entries.first?.appleKey, "item-1", "Apple に書けた直後の鍵も残る")

        reopened.finish([id])
        XCTAssertTrue(SaveJournal(file: journalFile()).entries.isEmpty, "済んだ記録は消す")
    }

    // MARK: - 次に開いたときの扱い

    func testRecoveryActionsUseOnlyTheRecordedKey() {
        XCTAssertEqual(JournalRecovery.action(for: entry(key: "item-1"), isLinked: true, itemExists: true, canTrustAbsence: true),
                       .linked)
        XCTAssertEqual(JournalRecovery.action(for: entry(key: "item-1"), isLinked: false, itemExists: true, canTrustAbsence: true),
                       .adopt(key: "item-1"), "記録した鍵の予定があれば、その鍵で結び付け直す（重複して作らない）")
        XCTAssertEqual(JournalRecovery.action(for: entry(key: "item-1"), isLinked: false, itemExists: false, canTrustAbsence: true),
                       .drop, "鍵の予定がないと確かめられたら、書けていない")
        XCTAssertEqual(JournalRecovery.action(for: entry(key: "item-1"), isLinked: false, itemExists: false, canTrustAbsence: false),
                       .keep, "権限がないなど、確かめられないときは残す")
        var started = entry()
        started.writeStarted = true
        XCTAssertEqual(JournalRecovery.action(for: started, isLinked: false, itemExists: nil, canTrustAbsence: true),
                       .askUser, "書き始めたのに鍵がない（書けたか分からない）ときは、自動で書き直さず、確かめてもらう")
        XCTAssertEqual(JournalRecovery.action(for: entry(), isLinked: false, itemExists: nil, canTrustAbsence: true),
                       .drop, "書き始めていなければ、何も書いていない（複数日の、まだ書いていない日など）")
        XCTAssertEqual(JournalRecovery.action(for: entry(movedFrom: UUID()), isLinked: true, itemExists: false, canTrustAbsence: true),
                       .askUser, "「Apple Calendarに保存」で作った予定が Apple 側で消えていたら、作ってあるとは言わない")
    }

    @MainActor
    func testAppleEntriesAreNotClearedBeforeRecovery() throws {
        // 前回：Apple に書けて設定も保存できたが、結び付けをファイルに書けないまま終わった
        var pending = entry(key: "item-1")
        pending.created = true
        pending.metadataSaved = true
        let journal = SaveJournal(file: journalFile())
        journal.begin([pending])

        // 次に開いた：作成画面はつなぐ前に作られる
        let store = ScheduleEditorStore(repository: SwitchableEventRepository(InMemoryEventRepository()),
                                        metadataRepository: InMemoryEventMetadataRepository(), journal: journal)
        store.refresh()
        XCTAssertNotNil(journal.entry(id: pending.id), "Apple とつないで結び付け直すまで、記録を消さない")
    }

    // MARK: - 端末の中の保存の復旧（連携していないとき）

    @MainActor
    func testLocalSaveGetsItsSettingsAfterRestart() throws {
        let localFile = JSONFile<[CalendarEvent]>(url: directory.appendingPathComponent("events.json"), empty: [])
        let metadataFile = JSONFile<[UUID: TimyCueEventMetadata]>(url: directory.appendingPathComponent("metadata.json"), empty: [:])
        // 予定は書けたが、設定を保存する前にアプリが終わった
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社")
        try FileEventRepository(file: localFile).insert([event])
        let journal = SaveJournal(file: journalFile())
        journal.begin([entry(event.id, isApple: false, arrival: 25)])
        // 書けなかった予定の記録（端末の中の保存は、書けたか書けていないかのどちらか）
        let notWritten = UUID()
        journal.begin([entry(notWritten, isApple: false)])

        // 次に開いた
        let local = FileEventRepository(file: localFile)
        let metadata = FileEventMetadataRepository(file: metadataFile)
        let connection = CalendarConnection(eventStore: EKEventStore(), switchable: SwitchableEventRepository(local),
                                            localEvents: local, metadata: metadata,
                                            preferencesFile: JSONFile(url: directory.appendingPathComponent("prefs.json"),
                                                                      empty: CalendarPreferences()),
                                            journal: SaveJournal(file: journalFile()),
                                            onChange: { _, _ in })
        XCTAssertEqual(metadata.allMetadata()[event.id]?.arrivalTargetMinutes, 25, "書けた予定に、記録した設定を当てる")
        XCTAssertTrue(SaveJournal(file: journalFile()).entries.isEmpty, "済んだ記録・書けていない記録は消す")
        XCTAssertNil(connection.recoveryNotice, "端末の中の保存は、確かめてもらうことがない")
    }

    // MARK: - 「Apple Calendarに保存」の途中で終わったあと

    @MainActor
    func testMoveResumesAfterRestartWithoutCreatingAgain() throws {
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let local = InMemoryEventRepository(events: [localEvent])
        let apple = InMemoryEventRepository()
        let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green)
        let rules = SaveTargetRules(calendars: [home], preferences: CalendarPreferences(), systemDefaultID: "home")
        // 前回：Apple に作れたが、元の予定を消す前にアプリが終わった
        let created = CalendarEvent(day: day, startMinute: 600, title: "歯医者", source: .appleCalendar, calendarID: "home")
        try apple.insert([created])
        var moving = entry(created.id, key: "item-1", movedFrom: localEvent.id)
        moving.created = true
        SaveJournal(file: journalFile()).begin([moving])

        // 次に開いた
        let store = ScheduleEditorStore(repository: CombinedEventRepository(primary: apple, local: local),
                                        metadataRepository: InMemoryEventMetadataRepository(),
                                        journal: SaveJournal(file: journalFile()))
        store.setCalendars(rules)
        try store.startEditing(eventID: localEvent.id)
        XCTAssertFalse(store.moveNeedsConfirmation)
        let moved = try store.moveToAppleCalendar()
        XCTAssertEqual(moved.id, created.id, "前に作った Apple の予定を使い、作り直さない")
        XCTAssertEqual(apple.allEvents().count, 1)
        XCTAssertTrue(local.allEvents().isEmpty)
        XCTAssertTrue(SaveJournal(file: journalFile()).entries.isEmpty)
    }

    @MainActor
    func testUnconfirmedMoveStillAsksAfterRestart() throws {
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let local = InMemoryEventRepository(events: [localEvent])
        let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green)
        // 前回：Apple に作れたか分からないまま終わった（鍵がない）
        SaveJournal(file: journalFile()).begin([entry(UUID(), movedFrom: localEvent.id)])

        let store = ScheduleEditorStore(repository: CombinedEventRepository(primary: InMemoryEventRepository(), local: local),
                                        metadataRepository: InMemoryEventMetadataRepository(),
                                        journal: SaveJournal(file: journalFile()))
        store.setCalendars(SaveTargetRules(calendars: [home], preferences: CalendarPreferences(), systemDefaultID: "home"))
        try store.startEditing(eventID: localEvent.id)
        XCTAssertTrue(store.moveNeedsConfirmation, "再起動のあとも、確かめたかを聞いてから作る")
        XCTAssertThrowsError(try store.moveToAppleCalendar())
    }

    @MainActor
    func testSavedDaysAreClearedFromTheJournal() throws {
        let journal = SaveJournal(file: journalFile())
        let store = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository(),
                                        journal: journal)
        store.startNew(on: day)
        store.content.title = "A社"
        store.setStartMinute(600)
        try store.save()
        XCTAssertTrue(journal.entries.isEmpty, "結び付けと設定まで済んだら、記録を消す")
    }
}
