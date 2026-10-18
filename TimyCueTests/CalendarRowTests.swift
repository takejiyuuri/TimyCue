import XCTest
@testable import TimyCue

/// 作成・編集の画面の「カレンダー」の行と、保存の前の確かめ（spec §89.3・§89.4・Q97・Q99・Q110・Q111-4・Q113。S3）
@MainActor
final class CalendarRowTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 19)
    private let defaultCalendar = CalendarChoice(id: "default", title: "Default", sourceTitle: "iCloud", isWritable: true, color: .orange)
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green)
    private let work = CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue)
    private let shared = CalendarChoice(id: "shared", title: "チーム", sourceTitle: "Google", isWritable: false, color: .lavender)

    private func rules(_ kind: SaveTargetKind?, calendars: [CalendarChoice]? = nil, hidden: Set<String> = [],
                       displayOnly: Set<String> = [], systemDefault: String? = "home") -> SaveTargetRules {
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = kind
        preferences.hiddenCalendarIDs = hidden
        displayOnly.forEach { preferences.setHoliday(true, calendarID: $0) }
        return SaveTargetRules(calendars: calendars ?? [defaultCalendar, home, work, shared], preferences: preferences,
                               systemDefaultID: systemDefault)
    }

    private func makeStore(local: [CalendarEvent] = [], apple: [CalendarEvent] = [], rules: SaveTargetRules?)
        -> (store: ScheduleEditorStore, local: InMemoryEventRepository, apple: InMemoryEventRepository) {
        let localRepository = InMemoryEventRepository(events: local)
        let appleRepository = InMemoryEventRepository(events: apple)
        let store = ScheduleEditorStore(repository: CombinedEventRepository(primary: appleRepository, local: localRepository),
                                        metadataRepository: InMemoryEventMetadataRepository())
        store.setCalendars(rules)
        return (store, localRepository, appleRepository)
    }

    private func fillNewEvent(_ store: ScheduleEditorStore) {
        store.startNew(on: day)
        store.content.title = "A社"
        store.setStartMinute(600)
    }

    // MARK: - 新規・コピーの行（Q97・Q110）

    func testTheNewEventRowCountsTimyCueOnly() {
        let store = makeStore(rules: nil).store
        store.startNew(on: day)
        XCTAssertFalse(store.showsCalendarRow, "連携していないときは TimyCue のみしかないので出さない（Q97）")

        store.setCalendars(rules(.appleCalendar, calendars: [home, shared]))
        XCTAssertTrue(store.showsCalendarRow, "TimyCue のみと、使える Apple カレンダー 1 つで 2 種類")
        XCTAssertEqual(store.calendarRowChoices, [.timyCueOnly, .calendar("home")], "書き込めないカレンダーは候補にしない")

        store.setCalendars(rules(.timyCueOnly, calendars: [home, shared], hidden: ["home"]))
        XCTAssertFalse(store.showsCalendarRow, "使える Apple カレンダーがなく、今の保存先（TimyCue のみ）が使えるなら出さない")

        store.setCalendars(rules(.appleCalendar, calendars: [home, shared], hidden: ["home"]))
        XCTAssertTrue(store.showsCalendarRow, "今の保存先が使えなければ、TimyCue のみ 1 つでも出して選び直せるようにする（Q110）")
        XCTAssertEqual(store.calendarRowChoices, [.timyCueOnly])
    }

    func testTheNewEventRowValuesAndNotes() {
        let store = makeStore(rules: rules(.timyCueOnly)).store
        store.startNew(on: day)
        XCTAssertEqual(store.valueTexts(for: .calendar), ["TimyCue のみ（このiPhone）", "TimyCue のみ"],
                       "この iPhone の中の保存だとはっきり示す（短い言い方も渡す）")
        XCTAssertEqual(store.selectedSaveChoice, .timyCueOnly)
        XCTAssertEqual(store.calendarRowNote, SaveTargetRules.timyCueOnlyNote, "spec §89.2 の推奨の文")

        store.chooseSaveTarget(.calendar("home"))
        XCTAssertEqual(store.calendarRowValue, "家")
        XCTAssertEqual(store.selectedSaveChoice, .calendar("home"))
        XCTAssertTrue(store.calendarRowNote?.contains("この予定だけに使います") ?? false)
        XCTAssertEqual(store.saveTargets.preferences.saveTargetKind, .timyCueOnly, "行で選んでも設定の既定は変えない（Q99）")

        store.setCalendars(rules(.appleCalendar))
        store.startNew(on: day)
        XCTAssertEqual(store.valueTexts(for: .calendar), ["iPhoneの既定（家）", "家"], "実際の名前を添える（Q106）")

        store.setCalendars(rules(.askBeforeSaving))
        store.startNew(on: day)
        XCTAssertEqual(store.valueTexts(for: .calendar), ["未選択"])
        XCTAssertNil(store.selectedSaveChoice)
        XCTAssertEqual(store.calendarRowNote, "保存先を選んでください。")
    }

    func testACopyFromAnUnusableCalendarShowsTheRowAndThePrompt() throws {
        let original = CalendarEvent(day: day, startMinute: 600, title: "共有の会議", source: .appleCalendar, calendarID: "shared")
        let (store, local, apple) = makeStore(apple: [original], rules: rules(.timyCueOnly, calendars: [shared]))
        try store.startEditing(eventID: original.id)
        try store.startCopy()
        let target = day.adding(days: 7)
        store.toggleCopyDestination(target)
        store.setStartMinute(600, on: target)

        XCTAssertTrue(store.showsCalendarRow, "コピー元の保存先（書き込めない）が使えないので、TimyCue のみ 1 つでも行を出す（Q97・Q110）")
        let prompt = try XCTUnwrap(store.saveTargetPrompt, "保存の前に選び直してもらう")
        XCTAssertEqual(prompt.problem, .readOnly(calendarTitle: "チーム"))
        XCTAssertNil(prompt.hiddenCalendarID)
        XCTAssertEqual(store.saveTargetPromptChoices, [.timyCueOnly])

        store.chooseSaveTarget(.timyCueOnly)
        XCTAssertTrue(store.showsCalendarRow, "選び直したあとも、選んだ値が見えるように行を出したまま")
        XCTAssertNil(store.saveTargetPrompt)
        try store.save()
        XCTAssertEqual(apple.allEvents().map(\.id), [original.id], "書き込めないカレンダーには書かない")
        XCTAssertEqual(local.allEvents().map(\.day), [target])
    }

    // MARK: - 既存の予定の行（Q113）

    func testALocalEventShowsThatItIsOnThisIPhone() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let store = makeStore(local: [event], rules: nil).store
        try store.startEditing(eventID: event.id)
        XCTAssertTrue(store.visibleRows.contains(.calendar), "既存の予定は所属をいつも出す（Q113）")
        XCTAssertEqual(store.valueTexts(for: .calendar), ["TimyCue のみ（このiPhone）", "TimyCue のみ"])
        XCTAssertTrue(store.isLocked(.calendar), "連携していなければ変えられないので閲覧専用")
        store.toggleRow(.calendar)
        XCTAssertNil(store.expandedRow, "閲覧専用の行は開かない")
        XCTAssertFalse(store.canMoveToAppleCalendar, "連携していないときは「Apple Calendarに保存」を出さない")

        store.setCalendars(rules(.timyCueOnly))
        try store.startEditing(eventID: event.id)
        XCTAssertEqual(store.calendarRowValue, "TimyCue のみ（このiPhone）", "値は所属のまま")
        XCTAssertFalse(store.isLocked(.calendar))
        XCTAssertTrue(store.calendarRowIsMoveTarget)
        XCTAssertEqual(store.calendarRowChoices, [.calendar("default"), .calendar("home"), .calendar("work")],
                       "チップは「Apple Calendarに保存」の移す先（使える Apple カレンダーだけ）")
        XCTAssertEqual(store.calendarRowNote, "「Apple Calendarに保存」の移す先を選びます。この予定は、このiPhoneに保存しています。")
        XCTAssertEqual(store.moveToAppleTargetName, "iPhoneの既定（家）", "TimyCue のみなら、使えるときの iPhone の既定（Q100）")

        store.chooseSaveTarget(.calendar("work"))
        XCTAssertEqual(store.moveToAppleTarget, .usable(work, source: .event))
        XCTAssertEqual(store.selectedSaveChoice, .calendar("work"))
        XCTAssertEqual(store.moveToAppleTargetName, "仕事")
        XCTAssertEqual(store.calendarRowValue, "TimyCue のみ（このiPhone）")
    }

    func testAnAppleEventShowsItsCalendar() throws {
        let appleEvent = CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar, calendarID: "home")
        let readOnly = CalendarEvent(day: day, startMinute: 700, title: "チーム定例", source: .appleCalendar, calendarID: "shared")
        let store = makeStore(apple: [appleEvent, readOnly], rules: rules(.timyCueOnly, calendars: [home, shared])).store
        try store.startEditing(eventID: appleEvent.id)
        XCTAssertTrue(store.showsCalendarRow)
        XCTAssertEqual(store.calendarRowValue, "家", "所属のカレンダーを出す")
        XCTAssertTrue(store.isLocked(.calendar), "変更先がなければ、所属を確かめられる閲覧専用の行（Q113）")

        store.setCalendars(rules(.timyCueOnly))
        try store.startEditing(eventID: appleEvent.id)
        XCTAssertFalse(store.isLocked(.calendar))
        XCTAssertFalse(store.calendarRowChoices.contains(.timyCueOnly), "Apple の予定を TimyCue のみへ移す操作は出さない")
        XCTAssertEqual(store.selectedSaveChoice, .calendar("home"))
        store.chooseSaveTarget(.calendar("work"))
        XCTAssertEqual(store.calendarRowValue, "仕事", "変えたなら変えた先")

        try store.startEditing(eventID: readOnly.id)
        XCTAssertEqual(store.calendarRowValue, "チーム（閲覧のみ）", "閲覧のみの予定と編集できる予定を区別する")
        XCTAssertTrue(store.isLocked(.calendar))
    }

    // MARK: - 初めて保存する前の確かめ（Q111-4）

    func testTheFirstSaveAsksForTheDefault() throws {
        let (store, local, apple) = makeStore(rules: rules(.askBeforeSaving))
        store.startNew(on: day)
        XCTAssertFalse(store.needsFirstSaveTargetChoice, "足りない項目があるときは、先に行で知らせる（§46）")
        store.content.title = "A社"
        store.setStartMinute(600)
        XCTAssertTrue(store.needsFirstSaveTargetChoice)
        XCTAssertTrue(store.showsCalendarRow, "まだ決まっていないので行も出す")
        XCTAssertEqual(store.firstSaveTargetOptions, [.timyCueOnly, .systemDefault, .calendar("default"), .calendar("work")],
                       "TimyCue のみ・iPhone の既定・それ以外の使えるカレンダー（iPhone の既定のカレンダーは重ねない）")
        XCTAssertFalse(store.hasMoreFirstSaveTargets)
        XCTAssertEqual(store.defaultTargetLabel(.timyCueOnly), "TimyCue のみ（このiPhone）")
        XCTAssertEqual(store.defaultTargetLabel(.systemDefault), "iPhoneの既定（家）")
        XCTAssertEqual(store.defaultTargetLabel(.calendar("work")), "仕事")
        XCTAssertEqual(store.eventChoice(for: .systemDefault), .calendar("home"))
        XCTAssertThrowsError(try store.save())
        XCTAssertTrue(local.allEvents().isEmpty)
        XCTAssertTrue(apple.allEvents().isEmpty, "決まるまで何も書かない")

        // 行でこの予定だけ選べば（「ほかのカレンダーを選ぶ」）、もう聞かない
        store.chooseSaveTarget(.calendar("work"))
        XCTAssertFalse(store.needsFirstSaveTargetChoice)

        store.setCalendars(nil)
        fillNewEvent(store)
        XCTAssertFalse(store.needsFirstSaveTargetChoice, "連携していないときは聞かずに、この iPhone の中へ保存する")
    }

    func testLongListsAreShortened() {
        let many = (1...6).map { CalendarChoice(id: "c\($0)", title: "カレンダー\($0)", sourceTitle: "iCloud", isWritable: true, color: .orange) }
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = .askBeforeSaving
        let store = makeStore(rules: SaveTargetRules(calendars: many, preferences: preferences, systemDefaultID: "c1")).store
        fillNewEvent(store)
        XCTAssertEqual(store.firstSaveTargetOptions,
                       [.timyCueOnly, .systemDefault, .calendar("c2"), .calendar("c3"), .calendar("c4")])
        XCTAssertTrue(store.hasMoreFirstSaveTargets, "多ければ「ほかのカレンダーを選ぶ」")

        preferences.saveTargetKind = .appleCalendar
        preferences.hiddenCalendarIDs = ["c1"]
        store.setCalendars(SaveTargetRules(calendars: many, preferences: preferences, systemDefaultID: "c1"))
        fillNewEvent(store)
        XCTAssertEqual(store.saveTargetPromptChoices, [.timyCueOnly, .calendar("c2"), .calendar("c3"), .calendar("c4"), .calendar("c5")])
        XCTAssertTrue(store.hasMoreSaveTargets)
    }

    // MARK: - 保存の前の選び直し（spec §89.4・E-10）

    func testThePromptBeforeSavingToAHiddenIPhoneDefault() throws {
        let (store, local, apple) = makeStore(rules: rules(.appleCalendar, hidden: ["default"], systemDefault: "default"))
        store.startNew(on: day)
        XCTAssertNil(store.saveTargetPrompt, "予定名などが足りないときは出さない（先に行で知らせる）")
        store.content.title = "A社"
        store.setStartMinute(600)
        let prompt = try XCTUnwrap(store.saveTargetPrompt)
        XCTAssertEqual(prompt.problem, .hidden(calendarTitle: "Default"))
        XCTAssertEqual(prompt.hiddenCalendarID, "default", "表示 OFF のときだけ「表示をONにして保存」を出せる（Q99）")
        XCTAssertEqual(prompt.calendarTitle, "Default")
        XCTAssertTrue(prompt.message.hasPrefix("保存先の「iPhoneの既定（Default）」は、TimyCue で表示を OFF にしています。"))
        XCTAssertTrue(prompt.message.contains("この予定だけに使います"))
        XCTAssertEqual(store.saveTargetPromptChoices, [.timyCueOnly, .calendar("home"), .calendar("work")],
                       "選び直す候補に TimyCue のみを含める。使えないカレンダーは出さない（spec §89.4）")
        XCTAssertEqual(store.promptButtonTitle(.timyCueOnly), "TimyCue のみ（このiPhone）に保存")
        XCTAssertEqual(store.promptButtonTitle(.calendar("home")), "「家」に保存")

        // 選び直しで TimyCue のみを選んで保存しても、設定は変えない
        store.chooseSaveTarget(.timyCueOnly)
        XCTAssertNil(store.saveTargetPrompt)
        try store.save()
        XCTAssertEqual(local.allEvents().count, 1)
        XCTAssertTrue(apple.allEvents().isEmpty)
        XCTAssertEqual(store.saveTargets.preferences.saveTargetKind, .appleCalendar, "この予定だけ。設定の既定は変えない（Q99）")
        XCTAssertEqual(store.saveTargets.preferences.hiddenCalendarIDs, ["default"], "表示の設定も勝手に変えない")
    }

    func testThePromptIsOnlyForNewLinkedEventsAndNeverOffersToUndoDisplayOnly() throws {
        let appleEvent = CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar, calendarID: "home")
        let store = makeStore(apple: [appleEvent], rules: rules(.appleCalendar, displayOnly: ["default"], systemDefault: "default")).store
        fillNewEvent(store)
        let prompt = try XCTUnwrap(store.saveTargetPrompt)
        XCTAssertEqual(prompt.problem, .displayOnly(calendarTitle: "Default"))
        XCTAssertNil(prompt.hiddenCalendarID, "表示のみの解除は、その場では勧めない（Q99）")

        try store.startEditing(eventID: appleEvent.id)
        XCTAssertNil(store.saveTargetPrompt, "編集では出さない（Apple の予定の所属を変える保存は、今までどおり止めて理由を出す）")

        store.setCalendars(nil)
        fillNewEvent(store)
        XCTAssertNil(store.saveTargetPrompt, "連携していないときは確かめない")
    }
}
