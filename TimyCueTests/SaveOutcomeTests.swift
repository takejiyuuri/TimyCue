import XCTest
@testable import TimyCue

/// 保存の途中の失敗・一部だけの成功・結果不明・押し直し・「Apple Calendarに保存」の途中の失敗（spec §89.9・2026-10-18 S1b）
final class SaveOutcomeTests: XCTestCase {
    private let day0 = CalendarDay(year: 2026, month: 10, day: 19)
    private var day1: CalendarDay { day0.adding(days: 1) }
    private var day2: CalendarDay { day0.adding(days: 2) }
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green)

    private var rules: SaveTargetRules {
        SaveTargetRules(calendars: [home], preferences: CalendarPreferences(), systemDefaultID: "home")
    }

    // MARK: - 1 件ずつ書く（InsertRun）

    func testInsertRunStopsAtTheFirstFailureAndReportsEachDay() {
        let events = [day0, day1, day2].map { CalendarEvent(day: $0, startMinute: 600, title: "A社") }
        let report = InsertRun.run(events, write: { _, index in
            if index == 1 { throw ScriptedEventRepository.Failure() }
        }, verify: { _, _ in .notSaved })
        XCTAssertEqual(report.saved.map(\.day), [day0])
        XCTAssertEqual(report.notSaved.map(\.day), [day1, day2], "失敗した日と、そのあと書かなかった日")
        XCTAssertTrue(report.unknown.isEmpty)
        XCTAssertNotNil(report.error)
        XCTAssertFalse(report.isComplete)
    }

    func testInsertRunTreatsAWriteThatTurnsOutSavedAsSaved() {
        let events = [day0, day1].map { CalendarEvent(day: $0, startMinute: 600, title: "A社") }
        let report = InsertRun.run(events, write: { _, index in
            if index == 0 { throw ScriptedEventRepository.Failure() }
        }, verify: { _, _ in .saved })
        XCTAssertEqual(report.saved.map(\.day), [day0, day1], "書けたあとに失敗が届いても、確かめて書けていれば成功（失敗と言わない）")
        XCTAssertTrue(report.isComplete)
    }

    func testInsertRunStopsWhenTheResultIsUnknown() {
        let events = [day0, day1, day2].map { CalendarEvent(day: $0, startMinute: 600, title: "A社") }
        let report = InsertRun.run(events, write: { _, index in
            if index == 1 { throw ScriptedEventRepository.Failure() }
        }, verify: { _, _ in .unknown })
        XCTAssertEqual(report.saved.map(\.day), [day0])
        XCTAssertEqual(report.unknown.map(\.day), [day1], "結果不明を保存していないとみなさない")
        XCTAssertEqual(report.notSaved.map(\.day), [day2], "結果不明のあとは書き続けない")
    }

    // MARK: - 書いたあとの確かめ（WriteVerification）

    func testWriteVerificationUsesOnlyFacts() {
        XCTAssertEqual(WriteVerification.insertOutcome(foundByIdentifier: true, lookalikes: 0, canTrustAbsence: false), .saved)
        XCTAssertEqual(WriteVerification.insertOutcome(foundByIdentifier: false, lookalikes: 1, canTrustAbsence: true), .unknown,
                       "識別子で引けず、似た予定があるだけなら、こちらが作ったものか区別できない（名前や日時だけで結び付けない）")
        XCTAssertEqual(WriteVerification.insertOutcome(foundByIdentifier: false, lookalikes: 0, canTrustAbsence: true), .notSaved)
        XCTAssertEqual(WriteVerification.insertOutcome(foundByIdentifier: false, lookalikes: 0, canTrustAbsence: false), .unknown,
                       "識別子が使えない・見つからないことを信じられないときは、保存していないと言わない")
        XCTAssertEqual(WriteVerification.deleteOutcome(stillExists: true, canTrustAbsence: true), .notSaved, "まだあれば消していない")
        XCTAssertEqual(WriteVerification.deleteOutcome(stillExists: false, canTrustAbsence: true), .saved, "消えていれば消せた")
        XCTAssertEqual(WriteVerification.deleteOutcome(stillExists: false, canTrustAbsence: false), .unknown)
    }

    func testOneAppleEventIsNeverLinkedToTwoEvents() {
        var links = EventKitLinks()
        let first = UUID()
        let second = UUID()
        links.setKey("item-1", for: first)
        XCTAssertEqual(links.setKey("item-1", for: second), first, "同じ鍵を持っていた前の結び付きを外す")
        XCTAssertNil(links.keys[first])
        XCTAssertEqual(links.keys[second], "item-1")
        XCTAssertNil(links.setKey("item-1", for: second), "同じ id へ結び直すだけなら何も外さない")
    }

    // MARK: - 複数日の一部だけの成功

    @MainActor
    private func makeStore(_ repository: EventRepository,
                           metadata: EventMetadataRepository = InMemoryEventMetadataRepository()) -> ScheduleEditorStore {
        ScheduleEditorStore(repository: repository, metadataRepository: metadata)
    }

    @MainActor
    private func fillThreeDays(_ store: ScheduleEditorStore) {
        store.startNew(on: day0)
        store.content.title = "A社"
        store.content.metadata.arrivalTargetMinutes = 15
        store.setStartMinute(600)
        store.addDay(day1)
        store.addDay(day2)
    }

    @MainActor
    func testPartialSaveKeepsOnlyUnsavedDaysAndRetriesThemWithoutDuplicates() throws {
        let repository = ScriptedEventRepository(script: [.saved, .notSaved])
        let metadata = InMemoryEventMetadataRepository()
        let store = makeStore(repository, metadata: metadata)
        fillThreeDays(store)

        XCTAssertThrowsError(try store.save()) { error in
            XCTAssertEqual(error as? ScheduleEditorError, .partiallySaved)
        }
        XCTAssertEqual(store.failure?.title, "一部の日だけ保存しました")
        XCTAssertTrue(store.failure?.message.contains("保存した日：10月19日（月）") ?? false)
        XCTAssertTrue(store.failure?.message.contains("保存していない日：10月20日（火）、10月21日（水）") ?? false,
                      "成功した日と保存していない日を分けて出す")
        XCTAssertFalse(store.failure?.closesEditor ?? true, "保存していない日が残るので、閉じずにもう一度保存できる")
        XCTAssertEqual(store.selectedDays, [day1, day2], "保存していない日だけを残す（成功した日は外す）")
        XCTAssertEqual(store.content.title, "A社", "入力はそのまま")
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertEqual(store.savedEventsThisSession.map(\.day), [day0])
        XCTAssertEqual(repository.allEvents().map(\.day), [day0])
        XCTAssertEqual(metadata.allMetadata()[repository.allEvents()[0].id]?.arrivalTargetMinutes, 15, "書けた日の設定は保存する")

        store.dismissFailure()
        let saved = try store.save()
        XCTAssertEqual(saved.map(\.day), [day1, day2], "再試行は保存していない日だけ")
        XCTAssertEqual(repository.allEvents().map(\.day).sorted(), [day0, day1, day2], "成功した日を重複して登録しない")
        XCTAssertEqual(repository.writeAttempts.map(\.day), [day0, day1, day1, day2])
        XCTAssertEqual(store.savedEventsThisSession.map(\.day).sorted(), [day0, day1, day2], "閉じるときは保存した全部の日を渡す")
        XCTAssertNil(store.failure)
        XCTAssertTrue(store.isFinished)
    }

    @MainActor
    func testUnknownDayIsNotSavedAgainAutomatically() throws {
        let repository = ScriptedEventRepository(script: [.saved, .unknown])
        let store = makeStore(repository)
        fillThreeDays(store)

        XCTAssertThrowsError(try store.save())
        XCTAssertEqual(store.failure?.title, "保存結果を確認できませんでした")
        XCTAssertTrue(store.failure?.message.contains("保存結果を確認できませんでした。重複を防ぐため、自動で再保存していません。") ?? false)
        XCTAssertTrue(store.failure?.message.contains("確認が必要な日：10月20日（火）") ?? false)
        XCTAssertTrue(store.failure?.message.contains("保存していない日：10月21日（水）") ?? false,
                      "失敗と結果不明を同じに扱わない")
        XCTAssertEqual(store.selectedDays, [day2], "結果不明の日は、保存していないとみなして残さない")

        store.dismissFailure()
        try store.save()
        XCTAssertEqual(repository.writeAttempts.map(\.day), [day0, day1, day2], "結果不明の日は書き直さない")
    }

    @MainActor
    func testOnlyUnknownClosesAfterTheNoticeAndIsNotSavedAgain() {
        let repository = ScriptedEventRepository(script: [.unknown])
        let store = makeStore(repository)
        store.startNew(on: day0)
        store.content.title = "A社"
        store.setStartMinute(600)

        XCTAssertThrowsError(try store.save())
        XCTAssertTrue(store.failure?.closesEditor ?? false, "保存するものが残らないので、知らせのあと閉じる")
        XCTAssertTrue(store.isFinished)
        XCTAssertThrowsError(try store.save()) { error in
            XCTAssertEqual(error as? ScheduleEditorError, .alreadySaved)
        }
        XCTAssertEqual(repository.writeAttempts.count, 1, "押し直しでも書かない")
    }

    @MainActor
    func testNothingWrittenKeepsTheInputAndSaysNotSaved() throws {
        let repository = ScriptedEventRepository(script: [.notSaved])
        let store = makeStore(repository)
        fillThreeDays(store)

        XCTAssertThrowsError(try store.save())
        XCTAssertEqual(store.failure?.title, "保存できませんでした")
        XCTAssertTrue(store.failure?.message.contains("予定は保存していません") ?? false)
        XCTAssertEqual(store.selectedDays, [day0, day1, day2], "1 日も書いていなければ、選んだ日はそのまま")
        XCTAssertFalse(store.isFinished)
        store.dismissFailure()
        XCTAssertEqual(try store.save().count, 3)
        XCTAssertEqual(repository.allEvents().count, 3)
    }

    // MARK: - 押し直し

    @MainActor
    func testConsecutivePressesDoNotSaveTwice() throws {
        let repository = ScriptedEventRepository()
        let store = makeStore(repository)
        fillThreeDays(store)
        XCTAssertEqual(try store.save().count, 3)
        XCTAssertThrowsError(try store.save(), "保存が済んだあとの押し直し（続けて 2 回押したなど）では書かない") { error in
            XCTAssertEqual(error as? ScheduleEditorError, .alreadySaved)
        }
        XCTAssertEqual(repository.allEvents().count, 3)
        XCTAssertNil(store.failure, "押し直しは知らせも出さない")

        store.startNew(on: day0)
        XCTAssertFalse(store.isFinished, "新しく始めたら、また保存できる")
    }

    @MainActor
    func testRetryAfterALocalFailureUsesTheSameIDs() throws {
        let local = ScriptedEventRepository(script: [.saved, .notSaved])
        let store = makeStore(local)
        fillThreeDays(store)
        XCTAssertThrowsError(try store.save())
        let firstAttemptID = try XCTUnwrap(local.writeAttempts.last?.id)
        store.dismissFailure()
        try store.save()
        XCTAssertEqual(local.writeAttempts.filter { $0.day == day1 }.map(\.id), [firstAttemptID, firstAttemptID],
                       "押し直しても同じ日は同じ id で書く（端末の中の保存では、同じ予定を 2 件にしない）")
    }

    // MARK: - 予定は書けたが、TimyCue の設定を保存できない

    @MainActor
    func testSettingsFailureAfterSavingIsNotCalledASaveFailure() throws {
        let repository = ScriptedEventRepository()
        let metadata = FailingMetadataRepository()
        metadata.failsOnSave = true
        let store = makeStore(repository, metadata: metadata)
        fillThreeDays(store)

        XCTAssertEqual(try store.save().count, 3, "予定は書けているので、保存は成功（押し直しで予定をもう 1 組作らない）")
        XCTAssertEqual(store.failure?.title, "予定を保存しました")
        XCTAssertTrue(store.failure?.message.contains("もう一度保存しなくてかまいません") ?? false)
        XCTAssertTrue(store.failure?.closesEditor ?? false)
        XCTAssertTrue(store.isFinished)

        metadata.failsOnSave = false
        store.refresh()
        let ids = repository.allEvents().map(\.id)
        XCTAssertEqual(ids.compactMap { metadata.allMetadata()[$0]?.arrivalTargetMinutes }, [15, 15, 15],
                       "保存できなかった設定は、あとでもう一度保存する")
    }

    @MainActor
    func testUnsavedSettingsAreShownWhenTheEventIsOpenedAgain() throws {
        var old = TimyCueEventMetadata()
        old.arrivalTargetMinutes = 10
        let event = CalendarEvent(day: day0, startMinute: 600, title: "A社")
        let repository = ScriptedEventRepository(events: [event])
        let metadata = FailingMetadataRepository()
        try metadata.save(old, for: event.id)
        metadata.failsOnSave = true
        let store = makeStore(repository, metadata: metadata)
        try store.startEditing(eventID: event.id)
        store.content.metadata.arrivalTargetMinutes = 30
        try store.save()
        XCTAssertEqual(store.failure?.title, "変更を保存しました")

        try store.startEditing(eventID: event.id)
        XCTAssertEqual(store.content.metadata.arrivalTargetMinutes, 30,
                       "保存できなかった設定を開き直したときに出す（古い値で上書きしない）")
    }

    @MainActor
    func testReadOnlyEventSettingsFailureIsAFailure() throws {
        let shared = CalendarChoice(id: "shared", title: "チーム", sourceTitle: "Google", isWritable: false, color: .green)
        let event = CalendarEvent(day: day0, startMinute: 600, title: "共有の会議", source: .appleCalendar, calendarID: "shared")
        let repository = ScriptedEventRepository(events: [event])
        let metadata = FailingMetadataRepository()
        metadata.failsOnSave = true
        let store = makeStore(repository, metadata: metadata)
        store.setCalendars(SaveTargetRules(calendars: [home, shared], preferences: CalendarPreferences(), systemDefaultID: "home"))
        try store.startEditing(eventID: event.id)
        XCTAssertTrue(store.areAppleFieldsLocked)
        store.content.metadata.arrivalTargetMinutes = 30

        XCTAssertThrowsError(try store.save(), "書き込めないカレンダーの予定は TimyCue の設定だけが変更なので、保存できなければ失敗")
        XCTAssertEqual(store.failure?.title, "保存できませんでした")
        XCTAssertTrue(store.savedEventsThisSession.isEmpty, "保存していないものを「保存した」として渡さない")
        XCTAssertFalse(store.isFinished)
    }

    @MainActor
    func testJournalKeepsSettingsUntilTheyAreSaved() throws {
        let journal = SaveJournal.inMemory()
        let metadata = FailingMetadataRepository()
        metadata.failsOnSave = true
        let store = ScheduleEditorStore(repository: ScriptedEventRepository(), metadataRepository: metadata, journal: journal)
        fillThreeDays(store)
        try store.save()
        XCTAssertEqual(journal.entries.count, 3, "設定を保存できるまで、記録を残す（途中でアプリが終わったら、次に開いたときに当てる）")
        XCTAssertTrue(journal.entries.allSatisfy { $0.created == true && $0.metadataSaved != true })

        metadata.failsOnSave = false
        store.refresh()
        XCTAssertTrue(journal.entries.isEmpty, "設定を保存できたら、記録を消す")
    }

    // MARK: - 削除

    @MainActor
    func testDeleteIsDoneEvenIfItsSettingsCannotBeRemoved() throws {
        let event = CalendarEvent(day: day0, startMinute: 600, title: "A社")
        let repository = ScriptedEventRepository(events: [event])
        let metadata = FailingMetadataRepository()
        try metadata.save(TimyCueEventMetadata(), for: event.id)
        metadata.failsOnDelete = true
        let store = makeStore(repository, metadata: metadata)
        try store.startEditing(eventID: event.id)

        XCTAssertNoThrow(try store.deleteEditingEvent(), "予定は消せた。設定を消せなくても失敗にしない（残っても使われない）")
        XCTAssertNil(store.failure)
        XCTAssertTrue(repository.allEvents().isEmpty)
        XCTAssertEqual(store.mode, .new)
    }

    @MainActor
    func testDeleteFailureAndUnknownAreToldApart() throws {
        let event = CalendarEvent(day: day0, startMinute: 600, title: "A社")
        let repository = ScriptedEventRepository(events: [event])
        let store = makeStore(repository)
        try store.startEditing(eventID: event.id)

        repository.deleteError = ScriptedEventRepository.Failure()
        XCTAssertThrowsError(try store.deleteEditingEvent())
        XCTAssertTrue(store.failure?.message.contains("予定は残っています") ?? false)
        store.dismissFailure()

        repository.deleteError = WriteCheckError.unconfirmed
        XCTAssertThrowsError(try store.deleteEditingEvent())
        XCTAssertEqual(store.failure?.title, "削除結果を確認できませんでした", "消えたか確かめられないときは、失敗と言わない")
    }

    // MARK: - 「Apple Calendarに保存」の途中の失敗（spec §89.5・§89.9）

    @MainActor
    private func makeMoveStore(local: ScriptedEventRepository, apple: ScriptedEventRepository,
                               metadata: EventMetadataRepository = InMemoryEventMetadataRepository()) -> ScheduleEditorStore {
        let store = ScheduleEditorStore(repository: CombinedEventRepository(primary: apple, local: local), metadataRepository: metadata)
        store.setCalendars(rules)
        return store
    }

    @MainActor
    func testMoveKeepsBothWhenTheLocalEventCannotBeDeletedAndResumesWithoutCreatingAgain() throws {
        let localEvent = CalendarEvent(day: day0, startMinute: 600, title: "歯医者")
        let local = ScriptedEventRepository(events: [localEvent])
        let apple = ScriptedEventRepository()
        let metadata = InMemoryEventMetadataRepository()
        var settings = TimyCueEventMetadata()
        settings.arrivalTargetMinutes = 20
        try metadata.save(settings, for: localEvent.id)
        let store = makeMoveStore(local: local, apple: apple, metadata: metadata)
        try store.startEditing(eventID: localEvent.id)

        local.deleteError = ScriptedEventRepository.Failure()
        XCTAssertThrowsError(try store.moveToAppleCalendar())
        XCTAssertEqual(store.failure?.title, "Apple Calendarに保存しました")
        XCTAssertTrue(store.failure?.message.contains("両方に残っています") ?? false)
        XCTAssertTrue(store.failure?.message.contains("どちらも自動では消しません") ?? false)
        XCTAssertTrue(store.failure?.closesEditor ?? false, "その場で押し直させない")
        XCTAssertEqual(apple.allEvents().count, 1)
        XCTAssertEqual(local.allEvents().map(\.id), [localEvent.id], "元の予定を失わない")
        XCTAssertThrowsError(try store.moveToAppleCalendar(), "閉じるまで押し直しても作らない")
        XCTAssertEqual(apple.writeAttempts.count, 1)

        // もう一度開いて押すと、Apple に作り直さず、続きから行う
        local.deleteError = nil
        try store.startEditing(eventID: localEvent.id)
        store.content.title = "歯医者（変更）"
        let moved = try store.moveToAppleCalendar()
        XCTAssertEqual(apple.writeAttempts.count, 1, "Apple に二重に作らない")
        XCTAssertEqual(apple.allEvents().map(\.id), [moved.id])
        XCTAssertEqual(apple.allEvents().first?.title, "歯医者（変更）", "今の内容で直してから続ける")
        XCTAssertTrue(local.allEvents().isEmpty)
        XCTAssertEqual(metadata.allMetadata()[moved.id]?.arrivalTargetMinutes, 20, "設定を引き継ぐ")
    }

    @MainActor
    func testResumedMoveThatCannotUpdateSaysTheAppleEventExists() throws {
        let localEvent = CalendarEvent(day: day0, startMinute: 600, title: "歯医者")
        let local = ScriptedEventRepository(events: [localEvent])
        let apple = ScriptedEventRepository()
        let store = makeMoveStore(local: local, apple: apple)
        try store.startEditing(eventID: localEvent.id)
        local.deleteError = ScriptedEventRepository.Failure()
        XCTAssertThrowsError(try store.moveToAppleCalendar())

        local.deleteError = nil
        apple.updateError = ScriptedEventRepository.Failure()
        try store.startEditing(eventID: localEvent.id)
        XCTAssertThrowsError(try store.moveToAppleCalendar())
        XCTAssertTrue(store.failure?.message.contains("前に作った予定があります") ?? false)
        XCTAssertFalse(store.failure?.message.contains("作っていません") ?? true, "Apple に予定があるのに、作っていないと言わない")
        XCTAssertFalse(store.failure?.closesEditor ?? true, "押し直しても作り直さないので、閉じずに試せる")
        XCTAssertEqual(apple.allEvents().count, 1)
        XCTAssertEqual(local.allEvents().map(\.id), [localEvent.id])

        store.dismissFailure()
        apple.updateError = nil
        XCTAssertNoThrow(try store.moveToAppleCalendar())
        XCTAssertEqual(apple.writeAttempts.count, 1, "最後まで Apple に作り直さない")
        XCTAssertTrue(local.allEvents().isEmpty)
    }

    @MainActor
    func testMoveKeepsTheLocalEventWhenSettingsCannotBeCarriedOver() throws {
        let localEvent = CalendarEvent(day: day0, startMinute: 600, title: "歯医者")
        let local = ScriptedEventRepository(events: [localEvent])
        let apple = ScriptedEventRepository()
        let metadata = FailingMetadataRepository()
        metadata.failsOnSave = true
        let store = makeMoveStore(local: local, apple: apple, metadata: metadata)
        try store.startEditing(eventID: localEvent.id)

        XCTAssertThrowsError(try store.moveToAppleCalendar())
        XCTAssertTrue(store.failure?.message.contains("設定を引き継げなかったため") ?? false)
        XCTAssertEqual(local.allEvents().map(\.id), [localEvent.id], "設定を持っている元の予定を消さない")
        XCTAssertEqual(apple.allEvents().count, 1)
    }

    @MainActor
    func testMoveWithAnUnknownResultAsksBeforeCreatingAgain() throws {
        let localEvent = CalendarEvent(day: day0, startMinute: 600, title: "歯医者")
        let local = ScriptedEventRepository(events: [localEvent])
        let apple = ScriptedEventRepository(script: [.unknown])
        let store = makeMoveStore(local: local, apple: apple)
        try store.startEditing(eventID: localEvent.id)

        XCTAssertThrowsError(try store.moveToAppleCalendar())
        XCTAssertEqual(store.failure?.title, "保存結果を確認できませんでした")
        XCTAssertTrue(store.failure?.message.contains("自動で作り直さず、TimyCue の中の予定も消していません") ?? false)
        XCTAssertEqual(local.allEvents().map(\.id), [localEvent.id])

        try store.startEditing(eventID: localEvent.id)
        XCTAssertTrue(store.moveNeedsConfirmation, "自動では判断できないので、ユーザーに確かめる")
        XCTAssertThrowsError(try store.moveToAppleCalendar()) { error in
            XCTAssertEqual(error as? ScheduleEditorError, .needsConfirmation)
        }
        XCTAssertEqual(apple.writeAttempts.count, 1, "確かめる前に作り直さない")
        XCTAssertNoThrow(try store.moveToAppleCalendar(confirmedUnknown: true))
        XCTAssertEqual(apple.writeAttempts.count, 2)
        XCTAssertTrue(local.allEvents().isEmpty)
    }

    // MARK: - メモリの中の保存先

    func testInMemoryInsertDoesNotDuplicate() throws {
        let repository = InMemoryEventRepository()
        let event = CalendarEvent(day: day0, startMinute: 600, title: "A社")
        try repository.insert([event])
        try repository.insert([event])
        XCTAssertEqual(repository.allEvents().count, 1)
    }
}

/// 決めた順に、書けた・書けなかった・結果不明を返す保存先（テスト用）。結果不明は、実際には書けている
private final class ScriptedEventRepository: EventRepository {
    struct Failure: Error {}
    private struct Unknown: Error {}

    private let base: InMemoryEventRepository
    private var script: [WriteOutcome]
    /// 書こうとした予定（順に）
    private(set) var writeAttempts: [CalendarEvent] = []
    var deleteError: Error?
    var updateError: Error?

    init(events: [CalendarEvent] = [], script: [WriteOutcome] = []) {
        base = InMemoryEventRepository(events: events)
        self.script = script
    }

    func allEvents() -> [CalendarEvent] { base.allEvents() }

    func insert(_ events: [CalendarEvent]) throws {
        let report = insertEach(events)
        if !report.isComplete { throw report.error ?? Failure() }
    }

    func insertEach(_ events: [CalendarEvent]) -> InsertReport {
        InsertRun.run(events, write: { event, _ in
            writeAttempts.append(event)
            let outcome: WriteOutcome = script.isEmpty ? .saved : script.removeFirst()
            switch outcome {
            case .saved: try base.insert([event])
            case .notSaved: throw Failure()
            case .unknown:
                try base.insert([event])
                throw Unknown()
            }
        }, verify: { [base] event, error in
            if error is Unknown { return .unknown }
            return base.allEvents().contains { $0.id == event.id } ? .saved : .notSaved
        })
    }

    func update(_ event: CalendarEvent) throws {
        if let updateError { throw updateError }
        try base.update(event)
    }

    func delete(id: UUID) throws {
        if let deleteError { throw deleteError }
        try base.delete(id: id)
    }
}

/// 保存・削除を決めて失敗させられる、TimyCue の設定の保存先（テスト用）
private final class FailingMetadataRepository: EventMetadataRepository {
    struct Failure: Error {}

    private let base = InMemoryEventMetadataRepository()
    var failsOnSave = false
    var failsOnDelete = false

    func allMetadata() -> [UUID: TimyCueEventMetadata] { base.allMetadata() }

    func save(_ metadata: TimyCueEventMetadata, for eventID: UUID) throws {
        if failsOnSave { throw Failure() }
        try base.save(metadata, for: eventID)
    }

    func saveAll(_ entries: [UUID: TimyCueEventMetadata]) throws {
        if failsOnSave { throw Failure() }
        try base.saveAll(entries)
    }

    func delete(for eventID: UUID) throws {
        if failsOnDelete { throw Failure() }
        try base.delete(for: eventID)
    }

    func deleteAll(_ eventIDs: Set<UUID>) throws {
        if failsOnDelete { throw Failure() }
        try base.deleteAll(eventIDs)
    }
}
