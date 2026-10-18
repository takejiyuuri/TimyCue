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
}
