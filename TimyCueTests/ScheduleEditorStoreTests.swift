import XCTest
@testable import TimyCue

@MainActor
final class ScheduleEditorStoreTests: XCTestCase {
    private let d1 = CalendarDay(year: 2026, month: 10, day: 12)
    private let d2 = CalendarDay(year: 2026, month: 10, day: 19)
    private let d3 = CalendarDay(year: 2026, month: 10, day: 26)
    private let d4 = CalendarDay(year: 2026, month: 11, day: 2)

    private func makeEvent(_ title: String, on day: CalendarDay, at minute: MinuteOfDay,
                           duration: Int? = nil, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(day: day, startMinute: minute, durationMinutes: duration, title: title, isAllDay: allDay)
    }

    private func makeStore(_ events: [CalendarEvent] = [],
                           metadata: [UUID: TimyCueEventMetadata] = [:])
        -> (store: ScheduleEditorStore, events: InMemoryEventRepository, metadata: InMemoryEventMetadataRepository) {
        let eventRepository = InMemoryEventRepository(events: events)
        let metadataRepository = InMemoryEventMetadataRepository(metadata: metadata)
        let store = ScheduleEditorStore(repository: eventRepository, metadataRepository: metadataRepository)
        return (store, eventRepository, metadataRepository)
    }

    // MARK: - 保存ボタンの文言（仕様 §60〜§62）

    func testSaveButtonTitleForNew() {
        let store = makeStore().store
        store.startNew(on: d1)
        XCTAssertEqual(store.saveButtonTitle, "保存")
        [d2, d3, d4].forEach(store.addDay)
        XCTAssertEqual(store.saveButtonTitle, "4件保存")
    }

    func testSaveButtonTitleForEditAndCopy() throws {
        let original = makeEvent("A社打合せ", on: d1, at: 600)
        let store = makeStore([original]).store
        try store.startEditing(eventID: original.id)
        XCTAssertEqual(store.saveButtonTitle, "変更を保存")
        XCTAssertEqual(store.mode.headerLabel, "編集中")

        try store.startCopy()
        XCTAssertEqual(store.mode.headerLabel, "コピー中")
        store.selectDay(d2)
        XCTAssertEqual(store.saveButtonTitle, "コピーを保存")
        [d3, d4, CalendarDay(year: 2026, month: 11, day: 9)].forEach(store.addDay)
        XCTAssertEqual(store.saveButtonTitle, "4件コピー")
    }

    // MARK: - 新規・複数日（仕様 §34〜§36・§60、2026-10-14 ユーザー決定「同じ内容で追加」、追加仕様書 vNext §1.2）

    func testNewMultipleDaysSavesOneEventPerDay() throws {
        let (store, events, metadata) = makeStore()
        store.startNew()
        store.selectDay(d3)
        store.setStartMinute(9 * 60)
        [d1, d2].forEach(store.addDay)
        XCTAssertEqual(store.selectedDays, [d1, d2, d3], "選択日は日付順に並ぶ")
        XCTAssertEqual(store.displayedDay, d3, "足しても左上の日は変わらない")
        XCTAssertEqual(store.additionalDays, [d1, d2], "最初に選んだ日のほかが「同じ内容で追加」で足した日")
        XCTAssertFalse(store.setsTimesIndividually, "初めは一括")
        XCTAssertEqual(store.startMinutes[d1], 9 * 60, "一括では、足した日も同じ時刻（2026-10-14 ユーザー決定）")

        store.setTimesIndividually(true)
        store.content.title = "通院"
        store.content.metadata.color = .lavender
        store.setStartMinute(14 * 60, on: d1)
        store.setStartMinute(14 * 60 + 30, on: d2)
        let saved = try store.save()

        XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(events.allEvents().count, 3)
        XCTAssertEqual(Set(saved.map(\.startMinute)), [840, 870, 540], "個別にすれば日ごとに違う時刻で保存できる")
        for event in saved {
            XCTAssertEqual(metadata.allMetadata()[event.id]?.color, .lavender, "TimyCue の情報は予定と別に保存する（仕様 §84）")
            XCTAssertEqual(store.metadata(for: event.id)?.color, .lavender)
        }
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testBatchKeepsTheSameTimeOnEveryDay() {
        let store = makeStore().store
        store.startNew(on: d1)
        store.addDay(d2)
        store.setStartMinute(600)
        XCTAssertEqual([d1, d2].map { store.startMinutes[$0] }, [600, 600], "一括：時刻を決めると全部の日に入る")
        store.selectDay(d2)
        store.setStartMinute(660)
        XCTAssertEqual([d1, d2].map { store.startMinutes[$0] }, [660, 660], "どの日を出していても全部の日が変わる")
        store.setEndMinute(720)
        XCTAssertEqual([d1, d2].map { store.durationMinutes(on: $0) }, [60, 60], "所要時間も全部の日で同じ")
        store.addDay(d3)
        XCTAssertEqual(store.startMinutes[d3], 660, "あとから足した日にも同じ時刻")
    }

    func testIndividualTimesAndBackToBatch() {
        let store = makeStore().store
        store.startNew(on: d1)
        store.setStartMinute(600)
        store.setEndMinute(660)
        store.addDay(d2)
        store.setTimesIndividually(true)
        XCTAssertEqual(store.startMinutes[d2], 600, "個別にしても、それまでの時刻は残る")
        store.selectDay(d2)
        store.setStartMinute(780)
        store.setEndMinute(870)
        XCTAssertEqual([d1, d2].map { store.startMinutes[$0] }, [600, 780], "個別：その日だけ変わる")
        XCTAssertEqual([d1, d2].map { store.durationMinutes(on: $0) }, [60, 90])
        store.addDay(d3)
        XCTAssertNil(store.startMinutes[d3], "個別のときに足した日は、時刻を日ごとに決める")

        XCTAssertTrue(store.batchChangesSomeDays, "日ごとに値が違うので、一括に戻す前に確かめる")
        XCTAssertEqual(store.batchConfirmationMessage, "すべて 13:00〜14:30 にそろえますか？", "今出している日（10/19）の値にそろえる")
        store.setTimesIndividually(false)
        XCTAssertEqual([d1, d2, d3].map { store.startMinutes[$0] }, [780, 780, 780],
                       "一括に戻すと、今左上に出している日の開始時刻にそろう（2026-10-14 決定）")
        XCTAssertEqual([d1, d2, d3].map { store.durationMinutes(on: $0) }, [90, 90, 90], "所要時間も")
        XCTAssertFalse(store.batchChangesSomeDays)
    }

    func testBackToBatchWithoutConfirmationWhenAllDaysAreTheSame() {
        let store = makeStore().store
        store.startNew(on: d1)
        store.setStartMinute(600)
        store.addDay(d2)
        store.setTimesIndividually(true)
        XCTAssertFalse(store.batchChangesSomeDays, "全部の日が同じ値なら、確かめずに一括へ切り替えてよい")
        XCTAssertEqual(store.batchConfirmationMessage, "すべて 10:00 にそろえますか？", "終了がなければ開始だけ")
    }

    func testConfirmStartTimeMovesToNextUnsetDay() {
        let store = makeStore().store
        store.startNew(on: d2)
        store.setTimesIndividually(true)
        [d1, d3].forEach(store.addDay)
        store.setStartMinute(600)
        XCTAssertEqual(store.confirmStartTime(), d3, "後ろの未設定の日へ移る")
        store.setStartMinute(660)
        XCTAssertEqual(store.confirmStartTime(), d1, "後ろに無ければ前の未設定の日へ戻る")
        store.setStartMinute(720)
        XCTAssertNil(store.confirmStartTime(), "全部決まったら移らない")
        XCTAssertEqual(store.displayedDay, d1)
    }

    func testTappingASelectedDayShowsItAndRemovingItShowsTheFirstDay() {
        let store = makeStore().store
        store.startNew(on: d1)
        [d2, d3].forEach(store.addDay)
        store.selectDay(d3)
        XCTAssertEqual(store.displayedDay, d3, "選んである日をタップすると、その日を左上に出す（その日の時刻を決めるため）")
        XCTAssertEqual(store.selectedDays, [d1, d2, d3], "選んである日をタップしても外れない")
        store.setStartMinute(600, on: d3)
        store.removeDay(d3)
        XCTAssertEqual(store.selectedDays, [d1, d2])
        XCTAssertEqual(store.displayedDay, d1, "左上の日を外したら、最初に選んだ日を出す")
        XCTAssertNil(store.startMinutes[d3], "外した日の時刻も消える")
        store.removeDay(d1)
        XCTAssertEqual(store.selectedDays, [d1, d2], "最初に選んだ日は外さない")
    }

    func testTappingAnUnselectedDayMovesTheShownDay() {
        let store = makeStore().store
        store.startNew(on: d1)
        store.setStartMinute(600)
        store.addDay(d2)
        store.selectDay(d3)
        XCTAssertEqual(store.selectedDays, [d2, d3], "左上の日を、タップした日へ動かす。足した日はそのまま")
        XCTAssertEqual(store.displayedDay, d3)
        XCTAssertEqual(store.startMinutes[d3], 600, "時刻も一緒に動く")
        XCTAssertNil(store.startMinutes[d1])
        XCTAssertEqual(store.baseDay, d3, "最初に選んだ日も動く")
        XCTAssertEqual(store.additionalDays, [d2])

        store.selectDay(d2)
        store.setStartMinute(700)
        store.selectDay(d4)
        XCTAssertEqual(store.selectedDays, [d3, d4], "足した日を左上に出してから別の日をタップすると、その日が動く")
        XCTAssertEqual(store.startMinutes[d4], 700)
        XCTAssertEqual(store.additionalDays, [d4])
    }

    func testAddingDaysOnlyWhileTheRowIsOpen() throws {
        let original = makeEvent("A社打合せ", on: d1, at: 600)
        let store = makeStore([original]).store
        store.startNew(on: d1)
        XCTAssertEqual(store.visibleRows.last, .additionalDays, "「同じ内容で追加」は右の入力のいちばん下")
        XCTAssertFalse(store.isAddingDays)
        store.toggleRow(.additionalDays)
        XCTAssertTrue(store.isAddingDays, "行を開いている間だけ、下のカレンダーで日を足したり外したりする")
        store.toggleRow(.title)
        XCTAssertFalse(store.isAddingDays, "ほかの行を開いたら終わる")

        try store.startEditing(eventID: original.id)
        XCTAssertFalse(store.visibleRows.contains(.additionalDays), "編集は 1 件だけなので出さない")
        store.addDay(d2)
        XCTAssertEqual(store.selectedDays, [d1])
    }

    func testAddingTheFirstDayWhenNothingIsSelectedChoosesIt() throws {
        let original = makeEvent("A社打合せ", on: d1, at: 600)
        let store = makeStore([original]).store
        try store.startEditing(eventID: original.id)
        try store.startCopy()
        store.toggleRow(.additionalDays)
        store.addDay(d3)
        XCTAssertEqual(store.selectedDays, [d3], "まだ日を選んでいなければ、足した日をその日にする")
        XCTAssertEqual(store.displayedDay, d3)
        XCTAssertEqual(store.baseDay, d3)
        XCTAssertTrue(store.additionalDays.isEmpty)
    }

    func testAdditionalDaysText() {
        let days = [
            CalendarDay(year: 2026, month: 10, day: 2), CalendarDay(year: 2026, month: 10, day: 3),
            CalendarDay(year: 2026, month: 10, day: 12), CalendarDay(year: 2026, month: 11, day: 21),
            CalendarDay(year: 2026, month: 11, day: 23), CalendarDay(year: 2026, month: 11, day: 24),
            CalendarDay(year: 2026, month: 11, day: 25), CalendarDay(year: 2026, month: 11, day: 26),
        ]
        let texts = ScheduleEditorStore.additionalDaysTexts(days)
        XCTAssertEqual(texts.first, "10/2・3・12　11/21・23-26",
                       "同じ月は「・」、3 日以上続く日は「23-26」、月が変わるところは全角の空き（2026-10-14 ユーザー決定）")
        XCTAssertEqual(Array(texts.dropFirst()), [
            "10/2・3・12　11/21 +4",
            "10/2・3・12 +5",
            "10/2・3 +6",
            "10/2 +7",
            "8日",
        ], "1 行に入らなければ、後ろを残りの日数「+N」にする")
        XCTAssertEqual(ScheduleEditorStore.additionalDaysTexts([]), ["なし"])
        XCTAssertEqual(ScheduleEditorStore.additionalDaysTexts([CalendarDay(year: 2026, month: 12, day: 31),
                                                                CalendarDay(year: 2027, month: 1, day: 1)]).first,
                       "12/31　1/1", "月をまたいで続く日はまとめない")
    }

    func testAdditionalDaysRowShowsOnlyTheAddedDays() {
        let store = makeStore().store
        store.startNew(on: d1)
        XCTAssertEqual(store.valueText(for: .additionalDays), "なし")
        [d2, d3].forEach(store.addDay)
        XCTAssertEqual(store.valueText(for: .additionalDays), "10/19・26", "最初に選んだ日（左上の日）は出さない")
    }

    func testDraftEventsReflectInputImmediately() {
        let store = makeStore().store
        store.startNew(on: d1)
        store.setStartMinute(870)
        store.content.title = "A社打合せ"
        XCTAssertEqual(store.draftEvents.first?.title, "A社打合せ", "入力欄の変更は仮予定に即反映（仕様 §39）")
        XCTAssertEqual(store.draftEvents.first?.startMinute, 870)
    }

    // MARK: - 必須項目（仕様 §46・Q3）

    func testSaveIssuesInOrderOfDateTimeTitle() {
        let store = makeStore().store
        store.startNew()
        XCTAssertEqual(store.saveIssues, [.noDaySelected, .missingTitle])
        store.selectDay(d1)
        store.setTimesIndividually(true)
        store.addDay(d2)
        store.setStartMinute(600, on: d1)
        XCTAssertEqual(store.saveIssues, [.missingStartTime([d2]), .missingTitle])
        store.setStartMinute(660, on: d2)
        store.content.title = "  "
        XCTAssertEqual(store.saveIssues, [.missingTitle], "空白だけの予定名は入っていないのと同じ")
        store.content.title = "A社打合せ"
        XCTAssertTrue(store.saveIssues.isEmpty)
    }

    func testSavingWithoutTitleOpensTitleRowAndShowsMessage() throws {
        let (store, events, _) = makeStore()
        store.startNew(on: d1)
        store.setStartMinute(600)
        XCTAssertNil(store.presentedIssue, "保存を押すまでは知らせない")

        XCTAssertThrowsError(try store.save()) { error in
            XCTAssertEqual(error as? ScheduleEditorError, .notReady([.missingTitle]))
        }
        XCTAssertTrue(events.allEvents().isEmpty, "予定名がないまま保存しない（Q3）")
        XCTAssertEqual(store.expandedRow, .title, "予定名の行を開く（仕様 §46）")
        XCTAssertEqual(store.presentedIssue?.message, "予定名を入力してください")

        store.content.title = "A社打合せ"
        XCTAssertNil(store.presentedIssue, "直したら知らせは消える")
        XCTAssertEqual(try store.save().count, 1)
    }

    func testSavingWithoutStartTimeShowsThatDay() {
        let store = makeStore().store
        store.startNew(on: d1)
        store.setTimesIndividually(true)
        [d2, d3].forEach(store.addDay)
        store.content.title = "通院"
        store.setStartMinute(600, on: d1)
        store.setStartMinute(600, on: d3)
        XCTAssertThrowsError(try store.save())
        XCTAssertEqual(store.displayedDay, d2, "時刻のない日を表示する")
        XCTAssertEqual(store.presentedIssue, .missingStartTime([d2]))
        XCTAssertEqual(store.presentedIssue?.message, "開始時刻を設定してください", "文言は Q7 で統一")
        XCTAssertNil(store.expandedRow, "予定名は入っているので行は開かない")
    }

    func testIssueMessages() {
        XCTAssertEqual(SaveIssue.noDaySelected.message, "日付を選んでください")
        XCTAssertEqual(SaveIssue.missingStartTime([]).message, "開始時刻を設定してください")
        XCTAssertEqual(SaveIssue.missingTitle.message, "予定名を入力してください")
    }

    // MARK: - 名前のない予定の編集（Q4）

    func testEditingUntitledExternalEventDoesNotRequireTitle() throws {
        var external = makeEvent("", on: d1, at: 600)
        external.locationName = "広島駅"
        external.source = .appleCalendar
        let (store, events, _) = makeStore([external])

        try store.startEditing(eventID: external.id)
        XCTAssertFalse(store.requiresTitle, "元から予定名がない予定は、編集では予定名を必須にしない")
        store.selectDay(d2)
        try store.save()
        XCTAssertEqual(events.allEvents().first?.day, d2)
        XCTAssertEqual(events.allEvents().first?.displayTitle, "広島駅", "表示は場所名にフォールバック（Q3）")
    }

    func testEditingTitledEventStillRequiresTitle() throws {
        let original = makeEvent("A社打合せ", on: d1, at: 600)
        let store = makeStore([original]).store
        try store.startEditing(eventID: original.id)
        XCTAssertTrue(store.requiresTitle)
        store.content.title = ""
        XCTAssertThrowsError(try store.save(), "予定名がある予定から予定名を消して保存はできない")
        XCTAssertEqual(store.expandedRow, .title)
    }

    func testCopyOfUntitledEventRequiresTitle() throws {
        let external = makeEvent("", on: d1, at: 600)
        let store = makeStore([external]).store
        try store.startEditing(eventID: external.id)
        try store.startCopy()
        XCTAssertTrue(store.requiresTitle, "コピーは TimyCue で新しく作る予定なので予定名が必須")
        store.selectDay(d2)
        store.setStartMinute(600, on: d2)
        XCTAssertEqual(store.saveIssues, [.missingTitle])
    }

    // MARK: - 終了時刻（仕様 §41・§69）

    func testEndMinuteIsOptionalAndMustBeAfterStart() {
        let store = makeStore().store
        store.startNew(on: d1)
        store.setStartMinute(600)
        XCTAssertNil(store.endMinute(on: d1), "何もしなければ終了は未設定")
        store.setEndMinute(570)
        XCTAssertNil(store.durationMinutes(on: d1), "開始より前の終了は入らない")
        store.setEndMinute(690)
        XCTAssertEqual(store.endMinute(on: d1), 690)
        store.setStartMinute(660)
        XCTAssertEqual(store.endMinute(on: d1), 750, "開始を動かすと所要時間を保ったまま終了も動く")
        store.setEndMinute(nil)
        XCTAssertNil(store.endMinute(on: d1))
    }

    // MARK: - 複数日の所要時間（Q1）

    func testDurationIsCommonFirstThenChangeableOnOneDay() throws {
        let store = makeStore().store
        store.startNew(on: d1)
        store.setTimesIndividually(true)
        [d2, d3, d4].forEach(store.addDay)
        store.content.title = "通院"
        for day in [d1, d2, d3, d4] { store.setStartMinute(600, on: day) }

        store.setEndMinute(660, on: d1)
        XCTAssertEqual([d1, d2, d3, d4].map { store.durationMinutes(on: $0) }, [60, 60, 60, 60],
                       "最初に入れた所要時間は全部の日に入る")

        store.selectDay(d2)
        store.setEndMinute(690)
        XCTAssertEqual([d1, d2, d3, d4].map { store.durationMinutes(on: $0) }, [60, 90, 60, 60],
                       "個別のとき、左上に出した日（下のカレンダーでタップした日）だけ変わる")

        store.setEndMinute(nil, on: d3)
        XCTAssertNil(store.durationMinutes(on: d3), "その日だけ終了未設定にもできる")
        XCTAssertEqual(store.durationMinutes(on: d4), 60)

        let saved = try store.save()
        XCTAssertEqual(saved.sorted { $0.day < $1.day }.map(\.durationMinutes), [60, 90, nil, 60],
                       "予定ごとに所要時間を持って保存する")
    }

    func testDurationSetWhileOneDayAppliesToDaysAddedLater() {
        let store = makeStore().store
        store.startNew(on: d1)
        store.setStartMinute(600)
        store.setEndMinute(660)
        store.setEndMinute(690)
        store.addDay(d2)
        XCTAssertEqual(store.durationMinutes(on: d2), 90, "1 日だけの間に変えた値は、あとで足した日にも入る")
    }

    func testDurationBackToCommonValueDropsOverride() {
        let store = makeStore().store
        store.startNew(on: d1)
        store.setTimesIndividually(true)
        store.addDay(d2)
        store.setStartMinute(600, on: d1)
        store.setStartMinute(600, on: d2)
        store.setEndMinute(660, on: d1)
        store.setEndMinute(690, on: d2)
        store.setEndMinute(660, on: d2)
        XCTAssertTrue(store.durationOverrides.isEmpty, "共通の値に戻したら、その日だけの値は消える")
    }

    func testDeselectingDayDropsItsDuration() {
        let store = makeStore().store
        store.startNew(on: d1)
        store.setTimesIndividually(true)
        store.addDay(d2)
        store.setStartMinute(600, on: d1)
        store.setStartMinute(600, on: d2)
        store.setEndMinute(660, on: d1)
        store.setEndMinute(690, on: d2)
        store.removeDay(d2)
        store.addDay(d2)
        XCTAssertEqual(store.durationMinutes(on: d2), 60, "外して選び直した日は共通の値に戻る")
    }

    // MARK: - 編集（仕様 §42・§61）

    func testEditingAnotherDayMovesTheEvent() throws {
        let original = makeEvent("A社打合せ", on: d1, at: 600, duration: 60)
        let (store, events, _) = makeStore([original])
        try store.startEditing(eventID: original.id)
        XCTAssertTrue(store.timedEvents(on: d1).isEmpty, "編集中の予定は保存済みの一覧から外して仮予定として出す")

        store.selectDay(d2)
        XCTAssertEqual(store.selectedDays, [d2], "編集は 1 日だけ")
        XCTAssertEqual(store.startMinutes[d2], 600, "移動しても時刻は保つ")
        XCTAssertEqual(store.durationMinutes(on: d2), 60, "移動しても所要時間は保つ")
        XCTAssertTrue(store.hasUnsavedChanges)

        try store.save()
        let saved = events.allEvents()
        XCTAssertEqual(saved.count, 1, "移動であって複製ではない")
        XCTAssertEqual(saved.first?.id, original.id)
        XCTAssertEqual(saved.first?.day, d2)
        XCTAssertEqual(saved.first?.durationMinutes, 60)
    }

    func testEditingKeepsNotesAndLoadsMetadata() throws {
        var original = makeEvent("A社打合せ", on: d1, at: 600)
        original.notes = "Apple カレンダーのメモ"
        var info = TimyCueEventMetadata()
        info.transport = .publicTransit
        let (store, events, _) = makeStore([original], metadata: [original.id: info])

        try store.startEditing(eventID: original.id)
        XCTAssertEqual(store.content.metadata.transport, .publicTransit)
        store.content.title = "A社定例"
        try store.save()
        XCTAssertEqual(events.allEvents().first?.notes, "Apple カレンダーのメモ", "メモは消さない（仕様 §55）")
        XCTAssertEqual(store.metadata(for: original.id)?.transport, .publicTransit)
    }

    // MARK: - コピー（仕様 §62・§63）

    func testCopyKeepsContentButNotDateTimeOrRepeat() throws {
        var original = makeEvent("A社打合せ", on: d1, at: 600, duration: 60)
        original.locationName = "広島市中区"
        original.notes = "資料を持参"
        var info = TimyCueEventMetadata()
        info.color = .mint
        info.arrivalTargetMinutes = 10
        info.transport = .car
        info.route = .preferHighway
        info.notifications = NotificationPreference(timings: [.beforeDeparture(minutes: 60), .atDeparture])
        let (store, events, _) = makeStore([original], metadata: [original.id: info])

        try store.startEditing(eventID: original.id)
        try store.startCopy()
        XCTAssertTrue(store.selectedDays.isEmpty, "日付は引き継がない")
        XCTAssertTrue(store.startMinutes.isEmpty, "開始時刻は引き継がない")
        XCTAssertEqual(store.content.repeatRule, .none)

        store.selectDay(d2)
        store.addDay(d3)
        store.setStartMinute(540, on: d2)
        store.setStartMinute(780, on: d3)
        let copies = try store.save()

        XCTAssertEqual(copies.count, 2)
        for copy in copies {
            XCTAssertNotEqual(copy.id, original.id)
            XCTAssertEqual(copy.title, "A社打合せ")
            XCTAssertEqual(copy.locationName, "広島市中区")
            XCTAssertEqual(copy.durationMinutes, 60, "所要時間は引き継ぐ")
            XCTAssertEqual(copy.notes, "資料を持参")
            XCTAssertEqual(store.metadata(for: copy.id), info, "色・到着目標・移動手段・ルート・通知を引き継ぐ")
        }
        XCTAssertEqual(events.allEvents().first(where: { $0.id == original.id }), original, "元の予定は変えない")
    }

    func testCopyRequiresEditMode() {
        let store = makeStore().store
        store.startNew(on: d1)
        XCTAssertThrowsError(try store.startCopy())
    }

    // MARK: - 未保存の変更（仕様 §66）

    func testUnsavedChangesAndDiscard() throws {
        let original = makeEvent("A社打合せ", on: d1, at: 600)
        let store = makeStore([original]).store
        try store.startEditing(eventID: original.id)
        XCTAssertFalse(store.hasUnsavedChanges)
        store.content.title = "B社打合せ"
        store.setEndMinute(660)
        XCTAssertTrue(store.hasUnsavedChanges)
        store.discardChanges()
        XCTAssertEqual(store.content.title, "A社打合せ")
        XCTAssertNil(store.durationMinutes(on: d1))
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    // MARK: - 右上の行（仕様 §44・§45・§52）

    func testOnlyOneRowIsExpandedAtATime() {
        let store = makeStore().store
        store.startNew(on: d1)
        store.toggleRow(.title)
        XCTAssertEqual(store.expandedRow, .title)
        store.toggleRow(.location)
        XCTAssertEqual(store.expandedRow, .location, "別の行を開くと前の行は閉じる")
        store.toggleRow(.location)
        XCTAssertNil(store.expandedRow, "同じ行をもう一度押すと閉じる")
    }

    func testRouteRowOnlyForCar() {
        let store = makeStore().store
        store.startNew(on: d1)
        XCTAssertFalse(store.visibleRows.contains(.route), "移動手段が自動のときはルートを出さない")
        store.content.metadata.transport = .car
        XCTAssertTrue(store.visibleRows.contains(.route))
        XCTAssertEqual(store.visibleRows.map(\.label),
                       ["予定名", "場所", "到着目標", "移動手段", "ルート", "通知", "色", "同じ内容で追加"],
                       "繰り返しの行は出さない（2026-10-13）。「終了」の行もなくした（下端のハンドルで決める。2026-10-14）。「同じ内容で追加」はいちばん下")
    }

    // MARK: - 時間画面の表示（仕様 §37・§43）

    func testTimedEventsExcludeAllDayAndAreSorted() {
        let store = makeStore([
            makeEvent("午後", on: d1, at: 900),
            makeEvent("終日", on: d1, at: 0, allDay: true),
            makeEvent("朝", on: d1, at: 540),
        ]).store
        XCTAssertEqual(store.timedEvents(on: d1).map(\.title), ["朝", "午後"])
        XCTAssertEqual(store.allDayEvents(on: d1).map(\.title), ["終日"])
        XCTAssertEqual(store.suggestedScrollMinute(for: d1), 510, "最初の予定の少し前（仕様 §43）")
        XCTAssertNil(store.suggestedScrollMinute(for: d2))
    }
}
