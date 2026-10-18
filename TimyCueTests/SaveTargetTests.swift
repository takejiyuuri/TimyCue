import XCTest
@testable import TimyCue

/// 新しい予定の保存先の決まりと、保存先が使えないとき・保存に失敗したときの作成画面（spec §89.2〜§89.5・§89.9。S1a）
final class SaveTargetTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 12)
    private let defaultCalendar = CalendarChoice(id: "default", title: "Default", sourceTitle: "iCloud", isWritable: true, color: .orange)
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green)
    private let work = CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue)
    private let holidays = CalendarChoice(id: "jp", title: "日本の祝日", sourceTitle: "購読", isWritable: false, color: .lavender, isHolidays: true)
    private let shared = CalendarChoice(id: "shared", title: "チーム", sourceTitle: "Google", isWritable: false, color: .green)

    private var all: [CalendarChoice] { [defaultCalendar, home, work, holidays, shared] }

    private func rules(hidden: Set<String> = [], displayOnly: Set<String> = [], settingsDefault: String? = nil,
                       systemDefault: String? = "default") -> SaveTargetRules {
        var preferences = CalendarPreferences()
        preferences.hiddenCalendarIDs = hidden
        displayOnly.forEach { preferences.setHoliday(true, calendarID: $0) }
        preferences.defaultCalendarID = settingsDefault
        return SaveTargetRules(calendars: all, preferences: preferences, systemDefaultID: systemDefault)
    }

    // MARK: - 決まり（SaveTargetRules）

    func testCandidatesAreShownWritableAndNotDisplayOnly() {
        let rules = rules(hidden: ["work"], displayOnly: ["home"])
        XCTAssertEqual(rules.candidates, [defaultCalendar],
                       "表示 OFF・手で表示のみにした書き込めるカレンダー・書き込めないカレンダーは候補にしない")
        XCTAssertEqual(rules.problem(with: "work"), .hidden(calendarTitle: "仕事"))
        XCTAssertEqual(rules.problem(with: "home"), .displayOnly(calendarTitle: "家"))
        XCTAssertEqual(rules.problem(with: "shared"), .readOnly(calendarTitle: "チーム"))
        XCTAssertEqual(rules.problem(with: "gone"), .notFound)
    }

    func testAutomaticDisplayOnlyIsReplacedByTheManualSetting() {
        var preferences = CalendarPreferences()
        let memo = CalendarChoice(id: "memo", title: "祝日メモ", sourceTitle: "iCloud", isWritable: true, color: .orange, isHolidays: true)
        preferences.setHoliday(false, calendarID: "memo")
        let rules = SaveTargetRules(calendars: [memo], preferences: preferences, systemDefaultID: "memo")
        XCTAssertEqual(rules.candidates, [memo], "手で表示のみを外したら、自動の判定で上書きしない（Q114）")
    }

    func testTheReportedCaseHiddenIPhoneDefaultIsNotUsed() {
        let resolution = rules(hidden: ["default"]).resolve(eventCalendarID: nil)
        XCTAssertEqual(resolution, .unavailable(.hidden(calendarTitle: "Default"), source: .systemDefault),
                       "iPhone の既定も、表示 OFF なら使わない（2026-10-17 の報告：Default を OFF にすると保存した予定が見えなくなった）")
    }

    func testAnUnusableChoiceIsNeverReplacedByAnotherCalendar() {
        XCTAssertEqual(rules(hidden: ["work"]).resolve(eventCalendarID: "work"),
                       .unavailable(.hidden(calendarTitle: "仕事"), source: .event),
                       "その予定だけの指定が使えなくても、設定の既定や iPhone の既定へ落ちない")
        XCTAssertEqual(rules(settingsDefault: "gone").resolve(eventCalendarID: nil),
                       .unavailable(.notFound, source: .settingsDefault),
                       "設定の既定が消えても、iPhone の既定へ勝手に切り替えない（v1.2 の自動の切り替えは廃止）")
        XCTAssertEqual(rules(systemDefault: nil).resolve(eventCalendarID: nil),
                       .unavailable(.noSystemDefault, source: .systemDefault),
                       "iPhone の既定が取れなくても、書き込める最初のカレンダーを選ばない")
    }

    func testUsableChoicesInOrder() {
        XCTAssertEqual(rules().resolve(eventCalendarID: nil), .usable(defaultCalendar, source: .systemDefault))
        XCTAssertEqual(rules(settingsDefault: "work").resolve(eventCalendarID: nil), .usable(work, source: .settingsDefault))
        XCTAssertEqual(rules(settingsDefault: "work").resolve(eventCalendarID: "home"), .usable(home, source: .event),
                       "その予定だけの保存先がいちばん優先")
    }

    func testLabels() {
        let usable = rules()
        XCTAssertEqual(usable.systemDefaultLabel, "iPhoneの既定（Default）", "実際の名前を添える（Q106）")
        XCTAssertEqual(usable.label(for: usable.resolve(eventCalendarID: nil)), "iPhoneの既定（Default）")
        XCTAssertEqual(usable.label(for: usable.resolve(eventCalendarID: "work")), "仕事")
        let hidden = rules(hidden: ["default", "work"])
        XCTAssertEqual(hidden.label(for: hidden.resolve(eventCalendarID: nil)), "iPhoneの既定（Default）（使えません）")
        XCTAssertEqual(hidden.label(for: hidden.resolve(eventCalendarID: "work")), "仕事（使えません）")
        let none = rules(systemDefault: nil)
        XCTAssertEqual(none.systemDefaultLabel, "iPhoneの既定", "名前が取れなければ「iPhoneの既定」とだけ")
        XCTAssertEqual(none.label(for: none.resolve(eventCalendarID: nil)), "iPhoneの既定（見つかりません）")
    }

    func testEveryEventIsCheckedBeforeAnythingIsWritten() {
        let rules = rules(hidden: ["work"])
        XCTAssertEqual(try rules.usableTargets(for: [nil, "home"]), [defaultCalendar, home])
        XCTAssertThrowsError(try rules.usableTargets(for: [nil, "work", "home"]),
                             "複数の日のうち 1 件でも使えなければ、何も書かずに止める（Apple へ書く直前の確かめ）") { error in
            XCTAssertEqual(error as? SaveTargetProblem, .hidden(calendarTitle: "仕事"))
        }
    }

    func testOldFallbackNoticeIsKeptInTheFile() throws {
        let json = #"{"hiddenCalendarIDs":[],"pendingFallbackNotice":true}"#
        let old = try JSONDecoder().decode(CalendarPreferences.self, from: Data(json.utf8))
        let again = try JSONDecoder().decode(CalendarPreferences.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(again.pendingFallbackNotice, true, "古い版の印は出さないが、S2 の移行まで消さない（Q110）")
    }

    // MARK: - 失敗の文（spec §89.9）

    func testFailureMessageForTheReportedCase() {
        let failure = EditorFailure.saveTarget(.hidden(calendarTitle: "Default"), source: .systemDefault,
                                               systemDefaultLabel: "iPhoneの既定（Default）", action: .save, canChooseInRow: true)
        XCTAssertEqual(failure.title, "保存できませんでした")
        XCTAssertTrue(failure.message.hasPrefix("保存先のカレンダーを確認してください。"), "決定 7 の例文")
        XCTAssertTrue(failure.message.contains("「iPhoneの既定（Default）」は、TimyCue で表示を OFF にしています"))
        XCTAssertTrue(failure.message.contains("予定は保存していません"))
        XCTAssertTrue(failure.message.contains("設定 ＞ カレンダー連携 で表示を ON にするか、新しい予定の保存先を変えてください"),
                      "表示を ON にするか、別の保存先を選ぶよう案内する")
        XCTAssertTrue(failure.message.contains("「カレンダー」の行で選んでください"))
    }

    func testFailureMessagesForOtherCases() {
        let readOnly = EditorFailure.saveTarget(.readOnly(calendarTitle: "チーム"), source: .event,
                                                systemDefaultLabel: "iPhoneの既定", action: .save, canChooseInRow: true)
        XCTAssertTrue(readOnly.message.contains("「チーム」には予定を書き込めません"))
        XCTAssertTrue(readOnly.message.contains("「カレンダー」の行で別のカレンダーを選んでください"),
                      "その予定だけの指定が使えないときは、まず行で選び直してもらう")
        let move = EditorFailure.saveTarget(.displayOnly(calendarTitle: "家"), source: .settingsDefault,
                                            systemDefaultLabel: "iPhoneの既定", action: .moveToApple, canChooseInRow: false)
        XCTAssertEqual(move.title, "Apple Calendarに保存できませんでした")
        XCTAssertTrue(move.message.contains("移していません"))
        XCTAssertTrue(move.message.contains("TimyCue の中の予定はそのまま残っています"))
        let written = EditorFailure.writeFailed(action: .save)
        XCTAssertTrue(written.message.contains("一部だけ保存されていることがあるため、カレンダーで確かめてから"),
                      "一部だけ書けたかを確かめられないときは、重複させないよう確かめてからやり直してもらう（S1b で分ける）")
        XCTAssertEqual(EditorFailure.writeFailed(action: .delete).title, "削除できませんでした")
    }

    // MARK: - 作成画面（ScheduleEditorStore）

    @MainActor
    private func makeStore(_ repository: CountingEventRepository, rules: SaveTargetRules?) -> ScheduleEditorStore {
        let store = ScheduleEditorStore(repository: repository, metadataRepository: InMemoryEventMetadataRepository())
        if let rules { store.setCalendars(rules) }
        return store
    }

    @MainActor
    private func fillNewEvent(_ store: ScheduleEditorStore) {
        store.startNew(on: day)
        store.content.title = "A社"
        store.setStartMinute(600)
    }

    @MainActor
    func testHiddenIPhoneDefaultIsRefusedBeforeWriting() {
        let repository = CountingEventRepository()
        let store = makeStore(repository, rules: rules(hidden: ["default"]))
        fillNewEvent(store)

        XCTAssertThrowsError(try store.save())
        XCTAssertEqual(repository.insertCount, 0, "何も書かずに止める（黙って保存しない・別のカレンダーへ移らない）")
        XCTAssertEqual(store.failure?.title, "保存できませんでした", "成功したように閉じず、理由を出す")
        XCTAssertTrue(store.failure?.message.contains("表示を OFF") ?? false)
        XCTAssertTrue(store.hasUnsavedChanges, "入力はそのまま")
        XCTAssertEqual(store.content.title, "A社")
        XCTAssertEqual(store.selectedDays, [day])
        XCTAssertTrue(store.showsCalendarRow, "今の保存先が使えないときは、選べるものがあれば行を出して選び直せる（Q110）")
        XCTAssertEqual(store.calendarRowValue, "iPhoneの既定（Default）（使えません）")
        XCTAssertEqual(store.valueTexts(for: .calendar), ["iPhoneの既定（Default）（使えません）", "Default（使えません）", "使えません"],
                       "行に入りきらなくても「使えません」が切れないよう、短い言い方も渡す（ビルド確認 #57 の画面写真）")
        XCTAssertNil(store.selectedSaveTargetID, "使えない保存先は選ばれていないことにする")
        XCTAssertFalse(store.saveTargetCandidates.contains(defaultCalendar), "使えないカレンダーは候補に出さない")

        store.content.calendarID = "home"
        XCTAssertNoThrow(try store.save(), "行で使える保存先を選べば保存できる")
        XCTAssertEqual(repository.insertCount, 1)
        XCTAssertEqual(repository.allEvents().first?.calendarID, "home")
        XCTAssertNil(store.failure)
    }

    @MainActor
    func testRowStaysAfterChoosingTheOnlyUsableCalendar() {
        let repository = CountingEventRepository()
        var preferences = CalendarPreferences()
        preferences.hiddenCalendarIDs = ["default"]
        let store = makeStore(repository, rules: SaveTargetRules(calendars: [defaultCalendar, home], preferences: preferences,
                                                                 systemDefaultID: "default"))
        fillNewEvent(store)
        XCTAssertTrue(store.showsCalendarRow, "使える保存先が 1 つでも、今の保存先が使えなければ行を出す（Q110）")
        store.content.calendarID = "home"
        XCTAssertTrue(store.showsCalendarRow, "選んだあとも行を出したままにして、選んだ値が見えるようにする")
        XCTAssertEqual(store.calendarRowValue, "家")
        XCTAssertEqual(store.selectedSaveTargetID, "home")
        XCTAssertNoThrow(try store.save())
        XCTAssertEqual(repository.allEvents().first?.calendarID, "home")
    }

    @MainActor
    func testAProblemFoundWhenWritingIsShownWithItsReason() {
        let repository = CountingEventRepository()
        repository.insertError = SaveTargetProblem.hidden(calendarTitle: "Default")
        let store = makeStore(repository, rules: rules())
        fillNewEvent(store)
        XCTAssertThrowsError(try store.save(), "画面で確かめたあとに、Apple へ書く直前の確かめで止まったとき（ほかの画面で設定が変わった直後など）")
        XCTAssertEqual(store.failure?.title, "保存できませんでした")
        XCTAssertTrue(store.failure?.message.contains("TimyCue で表示を OFF にしています") ?? false, "書き込みの失敗ではなく、保存先の理由を出す")
    }

    @MainActor
    func testDisplayOnlyCalendarIsRefused() {
        let repository = CountingEventRepository()
        let store = makeStore(repository, rules: rules(displayOnly: ["default"]))
        fillNewEvent(store)
        XCTAssertThrowsError(try store.save())
        XCTAssertEqual(repository.insertCount, 0)
        XCTAssertTrue(store.failure?.message.contains("表示のみのカレンダー") ?? false)
    }

    @MainActor
    func testUnusableSettingsDefaultIsNotRedirectedToTheIPhoneDefault() {
        let repository = CountingEventRepository()
        let store = makeStore(repository, rules: rules(settingsDefault: "gone"))
        fillNewEvent(store)
        XCTAssertThrowsError(try store.save())
        XCTAssertEqual(repository.insertCount, 0, "iPhone の既定（Default）が使えても、そちらへは黙って入れない")
        XCTAssertTrue(store.failure?.message.contains("見つかりません") ?? false)
    }

    @MainActor
    func testCopyFromReadOnlyCalendarAsksToChooseAgain() throws {
        let original = CalendarEvent(day: day, startMinute: 600, title: "共有の会議", source: .appleCalendar, calendarID: "shared")
        let repository = CountingEventRepository(events: [original])
        let store = makeStore(repository, rules: rules())
        try store.startEditing(eventID: original.id)
        try store.startCopy()
        let target = day.adding(days: 7)
        store.toggleCopyDestination(target)
        store.setStartMinute(600, on: target)

        XCTAssertThrowsError(try store.save(), "コピー元の保存先（書き込めない）を初めの選択にし、使えなければ選び直してもらう（Q97）")
        XCTAssertEqual(repository.insertCount, 0)
        XCTAssertTrue(store.showsCalendarRow)
        XCTAssertTrue(store.failure?.message.contains("「カレンダー」の行で別のカレンダーを選んでください") ?? false)

        store.content.calendarID = "work"
        XCTAssertNoThrow(try store.save())
        XCTAssertEqual(repository.allEvents().filter { $0.title == "共有の会議" }.count, 2)
        XCTAssertTrue(repository.allEvents().contains { $0.calendarID == "work" })
    }

    @MainActor
    func testMovingAnAppleEventIntoAHiddenCalendarIsRefused() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar, calendarID: "home")
        let repository = CountingEventRepository(events: [event])
        let store = makeStore(repository, rules: rules(hidden: ["work"]))
        try store.startEditing(eventID: event.id)
        store.content.calendarID = "work"
        XCTAssertThrowsError(try store.save())
        XCTAssertEqual(repository.updateCount, 0, "表示 OFF のカレンダーへ移すと TimyCue から消えて見えるので、移さない")
        XCTAssertTrue(store.failure?.message.contains("「仕事」は、TimyCue で表示を OFF にしています") ?? false)
    }

    @MainActor
    func testEditingInItsOwnCalendarIsNotChecked() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar, calendarID: "home")
        let repository = CountingEventRepository(events: [event])
        let store = makeStore(repository, rules: rules(hidden: ["default"]))
        try store.startEditing(eventID: event.id)
        store.content.title = "A社（変更）"
        XCTAssertNoThrow(try store.save(), "所属を変えない編集は、新しい予定の保存先が使えなくても止めない")
        XCTAssertEqual(repository.updateCount, 1)
        XCTAssertNil(store.failure)
    }

    @MainActor
    func testEditingALocalEventIsNotBlockedByAnOldCalendarChoice() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "歯医者", calendarID: "gone")
        let repository = CountingEventRepository(events: [event])
        let store = makeStore(repository, rules: rules(hidden: ["default"]))
        try store.startEditing(eventID: event.id)
        store.content.title = "歯医者（変更）"
        XCTAssertNoThrow(try store.save(), "端末の中の予定の編集は Apple へ書かないので、保存先を確かめない")
        XCTAssertEqual(repository.updateCount, 1)
    }

    @MainActor
    func testNotConnectedSavesWithoutCheckingCalendars() {
        let repository = CountingEventRepository()
        let store = makeStore(repository, rules: nil)
        fillNewEvent(store)
        XCTAssertNoThrow(try store.save(), "つないでいないときは端末の中に保存する（確かめる保存先がない）")
        XCTAssertEqual(repository.insertCount, 1)
        XCTAssertFalse(store.showsCalendarRow)
    }

    @MainActor
    func testWriteFailureKeepsInputAndIsReported() {
        let repository = CountingEventRepository()
        repository.failsOnInsert = true
        let store = makeStore(repository, rules: rules())
        fillNewEvent(store)
        XCTAssertThrowsError(try store.save())
        XCTAssertEqual(store.failure?.title, "保存できませんでした")
        XCTAssertTrue(store.failure?.message.contains("カレンダーで確かめてから") ?? false)
        XCTAssertTrue(store.hasUnsavedChanges, "成功したことにしない")

        store.dismissFailure()
        XCTAssertNil(store.failure)
        repository.failsOnInsert = false
        XCTAssertNoThrow(try store.save())
        XCTAssertNil(store.failure, "成功したら知らせは消える")
    }

    @MainActor
    func testMissingInputIsStillShownInTheRowNotAsAnAlert() {
        let store = makeStore(CountingEventRepository(), rules: rules(hidden: ["default"]))
        store.startNew(on: day)
        XCTAssertThrowsError(try store.save())
        XCTAssertNil(store.failure, "足りない項目は今までどおり行を開いて知らせる（§46）")
        XCTAssertNotNil(store.presentedIssue)
    }

    @MainActor
    func testDeleteFailureIsReported() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar, calendarID: "home")
        let repository = CountingEventRepository(events: [event])
        repository.failsOnDelete = true
        let store = makeStore(repository, rules: rules())
        try store.startEditing(eventID: event.id)
        XCTAssertThrowsError(try store.deleteEditingEvent())
        XCTAssertEqual(store.failure?.title, "削除できませんでした")
        XCTAssertEqual(store.mode, .edit(eventID: event.id), "閉じずに、編集の画面のまま")
    }

    // MARK: - 「Apple Calendarに保存」（spec §89.5）

    @MainActor
    func testMoveToAppleIsRefusedWhenTheTargetIsHidden() throws {
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let local = InMemoryEventRepository(events: [localEvent])
        let apple = InMemoryEventRepository()
        let store = ScheduleEditorStore(repository: CombinedEventRepository(primary: apple, local: local),
                                        metadataRepository: InMemoryEventMetadataRepository())
        store.setCalendars(rules(hidden: ["default"]))
        try store.startEditing(eventID: localEvent.id)

        XCTAssertTrue(store.canMoveToAppleCalendar, "ボタンは出す")
        XCTAssertNotNil(store.moveToAppleUnavailableReason, "移す先が使えないときは押せなくして理由を出す")
        XCTAssertThrowsError(try store.moveToAppleCalendar())
        XCTAssertTrue(apple.allEvents().isEmpty, "何も作らない")
        XCTAssertEqual(local.allEvents().map(\.id), [localEvent.id], "元の予定も消さない")
        XCTAssertEqual(store.failure?.title, "Apple Calendarに保存できませんでした")

        store.content.calendarID = "home"
        XCTAssertNil(store.moveToAppleUnavailableReason)
        XCTAssertNoThrow(try store.moveToAppleCalendar())
        XCTAssertEqual(apple.allEvents().map(\.calendarID), ["home"])
        XCTAssertTrue(local.allEvents().isEmpty)
    }

    @MainActor
    func testMoveWithOnlyOneUsableCalendarShowsTheRow() throws {
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let local = InMemoryEventRepository(events: [localEvent])
        let apple = InMemoryEventRepository()
        let store = ScheduleEditorStore(repository: CombinedEventRepository(primary: apple, local: local),
                                        metadataRepository: InMemoryEventMetadataRepository())
        var preferences = CalendarPreferences()
        preferences.hiddenCalendarIDs = ["default"]
        store.setCalendars(SaveTargetRules(calendars: [defaultCalendar, home], preferences: preferences, systemDefaultID: "default"))
        try store.startEditing(eventID: localEvent.id)

        XCTAssertTrue(store.showsCalendarRow, "移す先が使えないときは、使える保存先が 1 つでも行を出す")
        XCTAssertEqual(store.moveToAppleUnavailableReason,
                       "移す先の「iPhoneの既定（Default）」には移せません（表示 OFF）。「カレンダー」の行か、設定 ＞ カレンダー連携 で選び直してください。")
        store.content.calendarID = "home"
        XCTAssertTrue(store.showsCalendarRow)
        XCTAssertEqual(store.selectedSaveTargetID, "home")
        XCTAssertNil(store.moveToAppleUnavailableReason)
        XCTAssertNoThrow(try store.moveToAppleCalendar())
        XCTAssertEqual(apple.allEvents().map(\.calendarID), ["home"])
    }

    @MainActor
    func testMoveButtonExplainsWhenNoCalendarIsUsable() throws {
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let store = ScheduleEditorStore(repository: CombinedEventRepository(primary: InMemoryEventRepository(),
                                                                            local: InMemoryEventRepository(events: [localEvent])),
                                        metadataRepository: InMemoryEventMetadataRepository())
        store.setCalendars(rules(hidden: ["default", "home", "work"]))
        try store.startEditing(eventID: localEvent.id)
        XCTAssertTrue(store.canMoveToAppleCalendar)
        XCTAssertTrue(store.moveToAppleUnavailableReason?.contains("移せる Apple カレンダーがありません") ?? false)
    }
}

/// 書き込みの回数を数え、決めたところで失敗する保存先（テスト用）
private final class CountingEventRepository: EventRepository {
    struct Failure: Error {}

    private let base: InMemoryEventRepository
    var insertCount = 0
    var updateCount = 0
    var deleteCount = 0
    var failsOnInsert = false
    var failsOnDelete = false
    /// insert で投げるエラー（Apple へ書く直前の確かめで止まったときの代わり）
    var insertError: Error?

    init(events: [CalendarEvent] = []) {
        base = InMemoryEventRepository(events: events)
    }

    func allEvents() -> [CalendarEvent] { base.allEvents() }

    func insert(_ events: [CalendarEvent]) throws {
        insertCount += 1
        if let insertError { throw insertError }
        if failsOnInsert { throw Failure() }
        try base.insert(events)
    }

    func update(_ event: CalendarEvent) throws {
        updateCount += 1
        try base.update(event)
    }

    func delete(id: UUID) throws {
        deleteCount += 1
        if failsOnDelete { throw Failure() }
        try base.delete(id: id)
    }
}
