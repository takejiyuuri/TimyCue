import EventKit
import XCTest
@testable import TimyCue

/// 「TimyCue のみ」の保存（spec §89.2〜§89.5・§89.7・Q97・Q99・Q100・Q104。S2）：
/// 保存先の決まり・書く先の振り分け（この iPhone の中か Apple か）・取り違えの守り・重複候補の印
final class TimyCueOnlySaveTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 19)
    private let defaultCalendar = CalendarChoice(id: "default", title: "Default", sourceTitle: "iCloud", isWritable: true, color: .orange)
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

    private func rules(_ kind: SaveTargetKind?, settingsDefault: String? = nil, hidden: Set<String> = [],
                       systemDefault: String? = "home") -> SaveTargetRules {
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = kind
        preferences.defaultCalendarID = settingsDefault
        preferences.hiddenCalendarIDs = hidden
        return SaveTargetRules(calendars: [defaultCalendar, home, work], preferences: preferences, systemDefaultID: systemDefault)
    }

    // MARK: - 決まり（SaveTargetRules）

    func testTimyCueOnlyAndUndecidedDefaultsNeverFallToApple() {
        XCTAssertEqual(rules(.timyCueOnly).resolve(choice: nil), .timyCueOnly(source: .settingsDefault))
        XCTAssertEqual(rules(.askBeforeSaving).resolve(choice: nil), .notChosen,
                       "まだ決まっていなければ、iPhone の既定へ落ちずに確かめる（Q111-4）")
        XCTAssertEqual(rules(.appleCalendar).resolve(choice: nil), .usable(home, source: .systemDefault))
        XCTAssertEqual(rules(nil, settingsDefault: "work").resolve(choice: nil), .usable(work, source: .settingsDefault),
                       "種類のない設定（移行の前）は前の版と同じ Apple の決まり")
        XCTAssertEqual(rules(.timyCueOnly, settingsDefault: "work").resolve(eventCalendarID: nil), .timyCueOnly(source: .settingsDefault),
                       "「TimyCue のみ」でも、前に選んでいた Apple カレンダーは覚えたまま")
        XCTAssertTrue(rules(.timyCueOnly).resolve(choice: nil).isTimyCueOnly)
        XCTAssertNil(rules(.askBeforeSaving).resolve(choice: nil).problem)

        for kind in [SaveTargetKind.timyCueOnly, .askBeforeSaving] {
            XCTAssertThrowsError(try rules(kind).usableTargets(for: [nil]), "Apple へ書く直前の守り：TimyCue のみ・未選択の予定は Apple へ書かない") { error in
                XCTAssertEqual(error as? SaveRoutingError, .notAnAppleSave)
            }
        }
        XCTAssertEqual(try rules(.timyCueOnly).usableTargets(for: ["work"]), [work], "その予定だけ Apple を選んだら、その Apple カレンダー")
    }

    func testThisEventsChoiceComesBeforeTheDefault() {
        XCTAssertEqual(rules(.appleCalendar, settingsDefault: "work").resolve(choice: .timyCueOnly), .timyCueOnly(source: .event),
                       "既定が Apple でも、この予定だけ TimyCue のみにできる")
        XCTAssertEqual(rules(.timyCueOnly).resolve(choice: .calendar("work")), .usable(work, source: .event),
                       "既定が TimyCue のみでも、この予定だけ Apple にできる")
        XCTAssertEqual(rules(.timyCueOnly, hidden: ["work"]).resolve(choice: .calendar("work")),
                       .unavailable(.hidden(calendarTitle: "仕事"), source: .event), "使えない指定は TimyCue のみへ落ちない")
        XCTAssertEqual(rules(.appleCalendar).newEventChoices, [.timyCueOnly, .calendar("default"), .calendar("home"), .calendar("work")])
        XCTAssertEqual(rules(.appleCalendar, hidden: ["work"]).newEventChoices, [.timyCueOnly, .calendar("default"), .calendar("home")],
                       "選択肢は TimyCue のみと使える Apple カレンダーだけ（spec §89.2）")
    }

    func testTheMoveTargetFollowsTheSettingsKind() {
        XCTAssertEqual(rules(.timyCueOnly).resolveMoveTarget(eventCalendarID: "work"), .usable(work, source: .event))
        XCTAssertEqual(rules(.appleCalendar, settingsDefault: "work").resolveMoveTarget(eventCalendarID: nil),
                       .usable(work, source: .settingsDefault), "設定の保存先が Apple ならそれ（Q100）")
        XCTAssertEqual(rules(.timyCueOnly, settingsDefault: "work").resolveMoveTarget(eventCalendarID: nil),
                       .usable(home, source: .systemDefault), "TimyCue のみなら、使えるときの iPhone の既定（Q100）")
        XCTAssertEqual(rules(.askBeforeSaving).resolveMoveTarget(eventCalendarID: nil), .usable(home, source: .systemDefault))
        XCTAssertEqual(rules(.timyCueOnly, hidden: ["home"]).resolveMoveTarget(eventCalendarID: nil),
                       .unavailable(.hidden(calendarTitle: "家"), source: .systemDefault), "移す先は Apple カレンダーだけ。TimyCue のみは返さない")
    }

    func testNames() {
        let rules = rules(.timyCueOnly)
        XCTAssertEqual(rules.label(for: .timyCueOnly(source: .settingsDefault)), "TimyCue のみ（このiPhone）",
                       "この iPhone の中の保存だとはっきり示す（Q113）")
        XCTAssertEqual(rules.name(for: .timyCueOnly(source: .event)), "TimyCue のみ（このiPhone）")
        XCTAssertEqual(rules.label(for: .notChosen), "未選択")
        XCTAssertEqual(rules.choiceLabel(.timyCueOnly), "TimyCue のみ")
        XCTAssertEqual(rules.choiceLabel(.calendar("work")), "仕事")
        XCTAssertEqual(SaveTargetRules.timyCueOnlyNote,
                       "このiPhoneに保存します。Appleカレンダーやほかの端末とは同期しません。アプリを削除すると予定が失われる場合があります。",
                       "spec §89.2 の推奨の文")
    }

    // MARK: - 書く先の振り分け

    func testTheCombinedRepositoryWritesOnlyToTheChosenDestination() {
        let local = InMemoryEventRepository()
        let apple = InMemoryEventRepository()
        let combined = CombinedEventRepository(primary: apple, local: local)
        let mine = CalendarEvent(day: day, startMinute: 600, title: "TimyCue のみの予定")
        let theirs = CalendarEvent(day: day, startMinute: 700, title: "Apple の予定")
        XCTAssertTrue(combined.insertEach([mine], into: .onDevice).isComplete)
        XCTAssertTrue(combined.insertEach([theirs], into: .appleCalendar).isComplete)
        XCTAssertEqual(local.allEvents().map(\.id), [mine.id], "TimyCue のみはこの iPhone の中だけへ")
        XCTAssertEqual(apple.allEvents().map(\.id), [theirs.id], "Apple を選んだ予定は Apple だけへ")
    }

    func testTheDeviceFileRefusesAppleSavesAndKeepsTheMarkOnUpdate() throws {
        let url = directory.appendingPathComponent("events.json")
        let repository = FileEventRepository(file: JSONFile(url: url, empty: []))
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社")
        let refused = repository.insertEach([event], into: .appleCalendar)
        XCTAssertEqual(refused.notSaved.map(\.id), [event.id], "Apple 向けの予定を黙って端末の中へ入れない")
        XCTAssertEqual(refused.error as? SaveRoutingError, .destinationChanged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "何も書かない")

        var marked = event
        marked.savedOnDeviceWhileLinked = true
        XCTAssertTrue(repository.insertEach([marked], into: .onDevice).isComplete)
        var edited = event
        edited.title = "A社（変更）"
        try repository.update(edited)
        XCTAssertEqual(repository.allEvents().first?.savedOnDeviceWhileLinked, true, "編集で印を外さない")
        XCTAssertEqual(FileEventRepository(file: JSONFile(url: url, empty: [])).allEvents().first?.savedOnDeviceWhileLinked, true)
    }

    func testTheAppleRepositoryRefusesDeviceAndTimyCueOnlyEvents() throws {
        let linksURL = directory.appendingPathComponent("eventkit-links.json")
        var links = EventKitLinks()
        links.keys[UUID()] = "item-1"
        try JSONEncoder().encode(links).write(to: linksURL)
        let before = try Data(contentsOf: linksURL)
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = .timyCueOnly
        let settings = preferences
        let repository = EventKitEventRepository(store: EKEventStore(), metadata: InMemoryEventMetadataRepository(),
                                                 preferences: { settings }, journal: .inMemory(),
                                                 linksFile: JSONFile(url: linksURL, empty: EventKitLinks()))
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社")

        let onDevice = repository.insertEach([event], into: .onDevice)
        XCTAssertEqual(onDevice.notSaved.map(\.id), [event.id], "この iPhone の中へ書く予定を Apple へ入れない")
        XCTAssertEqual(onDevice.error as? SaveRoutingError, .destinationChanged)

        let apple = repository.insertEach([event], into: .appleCalendar)
        XCTAssertEqual(apple.notSaved.map(\.id), [event.id], "既定が TimyCue のみで保存先の指定のない予定は、Apple へ書かない")
        XCTAssertEqual(apple.error as? SaveRoutingError, .notAnAppleSave)
        XCTAssertEqual(try Data(contentsOf: linksURL), before, "結び付けも変えない")
    }

    // MARK: - 重複候補の印（Q104）

    func testDuplicatesSkipTimyCueOnlyEventsUnlessAMoveStopped() {
        let marked = CalendarEvent(day: day, startMinute: 600, title: "A社", savedOnDeviceWhileLinked: true)
        let plain = CalendarEvent(day: day, startMinute: 700, title: "B社")
        let apple = [CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar),
                     CalendarEvent(day: day, startMinute: 700, title: "B社", source: .appleCalendar)]
        XCTAssertEqual(DuplicateCandidates.find(local: [marked, plain], apple: apple, keptBoth: []).map(\.local.id), [plain.id],
                       "連携中に TimyCue のみを選んで作った予定は、自動の重複候補から外す")
        XCTAssertEqual(DuplicateCandidates.find(local: [marked, plain], apple: apple, keptBoth: [],
                                                pendingMoveLocalIDs: [marked.id]).map(\.local.id), [marked.id, plain.id],
                       "「Apple Calendarに保存」が途中で止まって両方に残った元の予定は、片方を選べるよう候補にする")
    }

    func testTheMarkIsWrittenOnlyWhenSet() throws {
        let plain = CalendarEvent(day: day, startMinute: 600, title: "A社")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        XCTAssertFalse(json.contains("savedOnDeviceWhileLinked"), "印のない予定のファイルの中身は前と同じ")
        var marked = plain
        marked.savedOnDeviceWhileLinked = true
        XCTAssertEqual(try JSONDecoder().decode(CalendarEvent.self, from: JSONEncoder().encode(marked)).savedOnDeviceWhileLinked, true)
    }

    func testChoosingACalendarClearsTimyCueOnly() {
        var content = EventContent()
        content.saveChoice = .timyCueOnly
        XCTAssertTrue(content.isTimyCueOnly)
        XCTAssertNil(content.calendarID)
        XCTAssertNil(content.makeEvent(day: day, startMinute: 600, durationMinutes: nil).calendarID)
        content.calendarID = "work"
        XCTAssertFalse(content.isTimyCueOnly, "カレンダーを選んだら TimyCue のみの選びは外れる")
        XCTAssertEqual(content.saveChoice, .calendar("work"))
        content.saveChoice = nil
        XCTAssertNil(content.saveChoice)
        XCTAssertNil(content.calendarID)
    }

    // MARK: - 作成画面の保存（S2-2）

    @MainActor
    private func makeLinkedStore(_ rules: SaveTargetRules, local: EventRepository, apple: EventRepository,
                                 metadata: EventMetadataRepository = InMemoryEventMetadataRepository(),
                                 journal: SaveJournal = .inMemory()) -> ScheduleEditorStore {
        let store = ScheduleEditorStore(repository: CombinedEventRepository(primary: apple, local: local),
                                        metadataRepository: metadata, journal: journal)
        store.setCalendars(rules)
        return store
    }

    @MainActor
    private func fillNewEvent(_ store: ScheduleEditorStore) {
        store.startNew(on: day)
        store.content.title = "A社"
        store.setStartMinute(600)
    }

    @MainActor
    func testATimyCueOnlyDefaultWhileLinkedSavesOnThisIPhoneWithTheMark() throws {
        let local = InMemoryEventRepository()
        let apple = InMemoryEventRepository()
        let store = makeLinkedStore(rules(.timyCueOnly), local: local, apple: apple)
        fillNewEvent(store)
        XCTAssertEqual(store.pendingSaveTarget, .timyCueOnly(source: .settingsDefault))
        try store.save()
        XCTAssertTrue(apple.allEvents().isEmpty, "連携中でも、TimyCue のみの予定は Apple へ書かない")
        XCTAssertEqual(local.allEvents().count, 1)
        XCTAssertEqual(local.allEvents().first?.savedOnDeviceWhileLinked, true, "連携中に TimyCue のみで保存した印（Q104）")
        XCTAssertNil(local.allEvents().first?.calendarID)
        XCTAssertNil(store.failure)
    }

    @MainActor
    func testChoosingAnAppleCalendarForThisEventDoesNotChangeTheDefault() throws {
        let local = InMemoryEventRepository()
        let apple = InMemoryEventRepository()
        let store = makeLinkedStore(rules(.timyCueOnly), local: local, apple: apple)
        fillNewEvent(store)
        store.content.saveChoice = .calendar("work")
        try store.save()
        XCTAssertEqual(apple.allEvents().map(\.calendarID), ["work"], "行で選んだ Apple カレンダーへ")
        XCTAssertNil(apple.allEvents().first?.savedOnDeviceWhileLinked)
        XCTAssertTrue(local.allEvents().isEmpty)
        XCTAssertEqual(store.saveTargets.preferences.saveTargetKind, .timyCueOnly, "この予定だけ。設定の既定は変えない（Q99）")
    }

    @MainActor
    func testChoosingTimyCueOnlyForThisEventKeepsTheAppleDefault() throws {
        let local = InMemoryEventRepository()
        let apple = InMemoryEventRepository()
        let store = makeLinkedStore(rules(.appleCalendar, settingsDefault: "work"), local: local, apple: apple)
        fillNewEvent(store)
        XCTAssertEqual(store.pendingSaveTarget, .usable(work, source: .settingsDefault))
        store.content.saveChoice = .timyCueOnly
        try store.save()
        XCTAssertTrue(apple.allEvents().isEmpty)
        XCTAssertEqual(local.allEvents().first?.savedOnDeviceWhileLinked, true)
        XCTAssertEqual(store.saveTargets.preferences.saveTargetKind, .appleCalendar, "設定の既定は変えない（Q99）")
        XCTAssertEqual(store.saveTargets.preferences.defaultCalendarID, "work")
    }

    @MainActor
    func testWithoutTheLinkEventsAreSavedOnThisIPhoneWithoutTheMark() throws {
        let local = InMemoryEventRepository()
        let apple = InMemoryEventRepository()
        let store = makeLinkedStore(rules(.appleCalendar, settingsDefault: "work"), local: local, apple: apple)
        store.setCalendars(nil)
        XCTAssertFalse(store.isConnectedToApple)
        fillNewEvent(store)
        XCTAssertNil(store.pendingSaveTarget, "連携していないときは保存先を確かめない")
        try store.save()
        XCTAssertTrue(apple.allEvents().isEmpty, "連携 OFF・許可なしでは Apple へ書かない（spec §89.6）")
        XCTAssertEqual(local.allEvents().count, 1)
        XCTAssertNil(local.allEvents().first?.savedOnDeviceWhileLinked, "連携していないときは印を付けない")
        XCTAssertNil(local.allEvents().first?.calendarID, "端末の中の予定には Apple カレンダーの指定を残さない")
    }

    @MainActor
    func testAnUndecidedDefaultStopsBeforeWriting() {
        let local = InMemoryEventRepository()
        let apple = InMemoryEventRepository()
        let store = makeLinkedStore(rules(.askBeforeSaving), local: local, apple: apple)
        fillNewEvent(store)
        XCTAssertThrowsError(try store.save()) { error in
            XCTAssertEqual(error as? ScheduleEditorError, .needsSaveTargetChoice)
        }
        XCTAssertTrue(local.allEvents().isEmpty, "保存先が決まるまで何も書かない（Q111-4）")
        XCTAssertTrue(apple.allEvents().isEmpty)
        XCTAssertNil(store.failure, "アラートではなく、保存の前の確かめで選んでもらう")
        XCTAssertEqual(store.expandedRow, .calendar)
        XCTAssertFalse(store.isFinished)
    }

    @MainActor
    func testATimyCueOnlySaveWhileLinkedIsRecoveredLikeALocalSave() throws {
        let eventsURL = directory.appendingPathComponent("events.json")
        let journalURL = directory.appendingPathComponent("save-journal.json")
        let local = FileEventRepository(file: JSONFile(url: eventsURL, empty: []))
        let store = makeLinkedStore(rules(.timyCueOnly), local: local, apple: InMemoryEventRepository(),
                                    metadata: RefusingMetadataRepository(),
                                    journal: SaveJournal(file: JSONFile(url: journalURL, empty: [])))
        fillNewEvent(store)
        store.content.metadata.arrivalTargetMinutes = 25
        let saved = try store.save()
        XCTAssertEqual(store.failure?.title, "予定を保存しました", "予定は書けた。設定はあとでもう一度保存する")
        let entries = SaveJournal(file: JSONFile(url: journalURL, empty: [])).entries
        XCTAssertEqual(entries.map(\.id), saved.map(\.id), "設定を保存できるまで、保存の途中の記録を残す")
        XCTAssertEqual(entries.first?.isApple, false, "実際に書いた先（この iPhone の中）の記録にする")

        // アプリが終わって、次に開いた：端末の中の保存として、記録した設定を当てる
        let reopened = FileEventRepository(file: JSONFile(url: eventsURL, empty: []))
        let metadata = InMemoryEventMetadataRepository()
        _ = CalendarConnection(eventStore: EKEventStore(), switchable: SwitchableEventRepository(reopened),
                               localEvents: reopened, metadata: metadata,
                               preferencesFile: JSONFile(url: directory.appendingPathComponent("prefs.json"), empty: CalendarPreferences()),
                               journal: SaveJournal(file: JSONFile(url: journalURL, empty: [])),
                               authorizationStatus: { .notDetermined },
                               onChange: { _, _ in })
        XCTAssertEqual(metadata.allMetadata()[saved[0].id]?.arrivalTargetMinutes, 25)
        XCTAssertTrue(SaveJournal(file: JSONFile(url: journalURL, empty: [])).entries.isEmpty, "済んだ記録は消す")
    }

    @MainActor
    func testAPartialLocalSaveCanBeFinishedInAnAppleCalendarWithoutDuplicates() throws {
        let local = StepRepository(script: [.saved, .notSaved])
        let apple = StepRepository()
        let store = makeLinkedStore(rules(.timyCueOnly), local: local, apple: apple)
        fillNewEvent(store)
        let day1 = day.adding(days: 1)
        let day2 = day.adding(days: 2)
        store.addDay(day1)
        store.addDay(day2)

        XCTAssertThrowsError(try store.save()) { error in
            XCTAssertEqual(error as? ScheduleEditorError, .partiallySaved)
        }
        XCTAssertEqual(local.allEvents().map(\.day), [day])
        XCTAssertEqual(store.selectedDays, [day1, day2], "保存していない日だけを残す")
        let firstTryID = try XCTUnwrap(local.writeAttempts.first(where: { $0.day == day1 })?.id)

        // 行で Apple カレンダーに替えて、もう一度保存する
        store.dismissFailure()
        store.content.saveChoice = .calendar("work")
        try store.save()
        XCTAssertEqual(local.allEvents().map(\.day), [day], "保存した日は重ねて書かない")
        XCTAssertEqual(apple.allEvents().map(\.day).sorted(), [day1, day2], "残った日だけを新しい保存先へ")
        XCTAssertEqual(apple.allEvents().first(where: { $0.day == day1 })?.id, firstTryID, "押し直しても同じ日は同じ id")
        XCTAssertTrue(apple.allEvents().allSatisfy { $0.calendarID == "work" && $0.savedOnDeviceWhileLinked == nil })
    }

    @MainActor
    func testACopyOfALocalEventStartsAsTimyCueOnly() throws {
        // 前の版で「Apple Calendarに保存」の移す先を選んだまま残っている指定
        let original = CalendarEvent(day: day, startMinute: 600, title: "歯医者", calendarID: "work")
        let local = InMemoryEventRepository(events: [original])
        let apple = InMemoryEventRepository()
        let store = makeLinkedStore(rules(.appleCalendar, settingsDefault: "work"), local: local, apple: apple)
        try store.startEditing(eventID: original.id)
        try store.startCopy()
        XCTAssertEqual(store.content.saveChoice, .timyCueOnly, "TimyCue の予定のコピーは TimyCue のみが初め（Q97）。残っていた移す先は使わない")
        XCTAssertEqual(store.copyInitialChoice, .timyCueOnly)
        XCTAssertEqual(store.pendingSaveTarget, .timyCueOnly(source: .event))

        let target = day.adding(days: 7)
        store.toggleCopyDestination(target)
        store.setStartMinute(600, on: target)
        XCTAssertEqual(try store.save().count, 1)
        XCTAssertTrue(apple.allEvents().isEmpty, "Apple には入らない")
        let copy = try XCTUnwrap(local.allEvents().first(where: { $0.day == target }))
        XCTAssertEqual(copy.savedOnDeviceWhileLinked, true)
        XCTAssertNil(copy.calendarID)
    }

    @MainActor
    func testACopyOfAnAppleEventStartsInItsCalendarAndCanBeKeptOnThisIPhone() throws {
        let original = CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar, calendarID: "work")
        let local = InMemoryEventRepository()
        let apple = InMemoryEventRepository(events: [original])
        let store = makeLinkedStore(rules(.timyCueOnly), local: local, apple: apple)
        try store.startEditing(eventID: original.id)
        try store.startCopy()
        XCTAssertEqual(store.pendingSaveTarget, .usable(work, source: .event), "Apple の予定のコピーは元のカレンダーが初め（Q97）")

        let target = day.adding(days: 7)
        store.toggleCopyDestination(target)
        store.setStartMinute(600, on: target)
        store.content.saveChoice = .timyCueOnly
        try store.save()
        XCTAssertEqual(apple.allEvents().map(\.id), [original.id], "TimyCue のみに替えたら Apple には入らない")
        XCTAssertEqual(local.allEvents().map(\.day), [target])
    }

    @MainActor
    func testEditingAMarkedEventKeepsTheMark() throws {
        let marked = CalendarEvent(day: day, startMinute: 600, title: "歯医者", savedOnDeviceWhileLinked: true)
        let local = InMemoryEventRepository(events: [marked])
        let store = makeLinkedStore(rules(.appleCalendar), local: local, apple: InMemoryEventRepository())
        try store.startEditing(eventID: marked.id)
        store.content.title = "歯医者（変更）"
        try store.save()
        XCTAssertEqual(local.allEvents().first?.title, "歯医者（変更）")
        XCTAssertEqual(local.allEvents().first?.savedOnDeviceWhileLinked, true, "編集で印を外さない（Q104）")
    }

    @MainActor
    func testMovingWithATimyCueOnlyDefaultUsesTheUsableIPhoneDefault() throws {
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let local = InMemoryEventRepository(events: [localEvent])
        let apple = InMemoryEventRepository()
        let store = makeLinkedStore(rules(.timyCueOnly), local: local, apple: apple)
        try store.startEditing(eventID: localEvent.id)
        XCTAssertTrue(store.canMoveToAppleCalendar)
        XCTAssertEqual(store.moveToAppleTarget, .usable(home, source: .systemDefault), "TimyCue のみなら、使えるときの iPhone の既定（Q100）")
        XCTAssertNil(store.moveToAppleUnavailableReason)
        try store.moveToAppleCalendar()
        XCTAssertEqual(apple.allEvents().map(\.calendarID), ["home"], "移す先をはっきり渡す")
        XCTAssertTrue(local.allEvents().isEmpty, "Apple に作れたと確かめてから、元の予定を消す（S1b の順のまま）")
    }

    @MainActor
    func testMovingIsRefusedWhenTheIPhoneDefaultCannotBeUsed() throws {
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let hidden = makeLinkedStore(rules(.timyCueOnly, hidden: ["default"], systemDefault: "default"),
                                     local: InMemoryEventRepository(events: [localEvent]), apple: InMemoryEventRepository())
        try hidden.startEditing(eventID: localEvent.id)
        XCTAssertTrue(hidden.moveToAppleUnavailableReason?.hasPrefix("移す先の「iPhoneの既定（Default）」には移せません（表示 OFF）") ?? false)

        let none = makeLinkedStore(rules(.timyCueOnly, hidden: ["default", "home", "work"], systemDefault: "default"),
                                   local: InMemoryEventRepository(events: [localEvent]), apple: InMemoryEventRepository())
        try none.startEditing(eventID: localEvent.id)
        XCTAssertTrue(none.moveToAppleUnavailableReason?.contains("移せる Apple カレンダーがありません") ?? false)
        XCTAssertThrowsError(try none.moveToAppleCalendar())
    }

    func testTheFailureMentionsTimyCueOnlyOnlyForNewEvents() {
        let save = EditorFailure.saveTarget(.hidden(calendarTitle: "Default"), source: .systemDefault,
                                            systemDefaultLabel: "iPhoneの既定（Default）", action: .save, canChooseInRow: true,
                                            offersTimyCueOnly: true)
        XCTAssertTrue(save.message.contains("「TimyCue のみ（このiPhone）」も選べます"), "選び直す候補に TimyCue のみを含める（spec §89.4）")
        XCTAssertTrue(save.message.contains("予定は保存していません"), "S1a の文はそのまま")
        let move = EditorFailure.saveTarget(.hidden(calendarTitle: "Default"), source: .systemDefault,
                                            systemDefaultLabel: "iPhoneの既定（Default）", action: .moveToApple, canChooseInRow: true,
                                            offersTimyCueOnly: true)
        XCTAssertFalse(move.message.contains("TimyCue のみ（このiPhone）」も選べます"), "移す先は Apple カレンダーだけ")
        XCTAssertTrue(EditorFailure.destinationChanged(action: .save).message.contains("予定は保存していません"))
    }

    @MainActor
    func testAnEditorThatThinksItIsLinkedWritesNothingToTheDeviceFile() throws {
        let url = directory.appendingPathComponent("events.json")
        let store = ScheduleEditorStore(repository: FileEventRepository(file: JSONFile(url: url, empty: [])),
                                        metadataRepository: InMemoryEventMetadataRepository())
        store.setCalendars(rules(.appleCalendar))
        fillNewEvent(store)
        XCTAssertThrowsError(try store.save(), "連携が切れた直後など、Apple 向けの予定を黙って端末の中へ入れない")
        XCTAssertTrue(store.failure?.message.contains("保存先の状態が変わったため") ?? false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.hasUnsavedChanges, "入力はそのまま")
    }
}

/// 決めた順に、書けた・書けなかったを返す保存先（テスト用）
private final class StepRepository: EventRepository {
    struct Failure: Error {}

    private let base = InMemoryEventRepository()
    private var script: [WriteOutcome]
    /// 書こうとした予定（順に）
    private(set) var writeAttempts: [CalendarEvent] = []

    init(script: [WriteOutcome] = []) {
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
            guard outcome == .saved else { throw Failure() }
            try base.insert([event])
        }, verify: { [base] event, _ in
            base.allEvents().contains { $0.id == event.id } ? .saved : .notSaved
        })
    }

    func update(_ event: CalendarEvent) throws { try base.update(event) }
    func delete(id: UUID) throws { try base.delete(id: id) }
}

/// TimyCue の設定をいつも保存できない保存先（テスト用）
private final class RefusingMetadataRepository: EventMetadataRepository {
    struct Failure: Error {}

    func allMetadata() -> [UUID: TimyCueEventMetadata] { [:] }
    func save(_ metadata: TimyCueEventMetadata, for eventID: UUID) throws { throw Failure() }
    func saveAll(_ entries: [UUID: TimyCueEventMetadata]) throws { throw Failure() }
    func delete(for eventID: UUID) throws {}
}
