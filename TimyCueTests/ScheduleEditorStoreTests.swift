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
        var content = EventContent()
        content.title = title
        content.durationMinutes = duration
        return CalendarEvent(day: day, startMinute: minute, content: content, isAllDay: allDay)
    }

    private func makeStore(_ events: [CalendarEvent] = []) -> (ScheduleEditorStore, InMemoryEventRepository) {
        let repository = InMemoryEventRepository(events: events)
        return (ScheduleEditorStore(repository: repository), repository)
    }

    // MARK: - 保存ボタンの文言（仕様 §34）

    func testSaveButtonTitleForNew() {
        let (store, _) = makeStore()
        store.startNew(on: d1)
        XCTAssertEqual(store.saveButtonTitle, "保存")
        [d2, d3, d4].forEach(store.selectDay)
        XCTAssertEqual(store.saveButtonTitle, "4件保存")
    }

    func testSaveButtonTitleForEditAndCopy() throws {
        let original = makeEvent("A社打合せ", on: d1, at: 600)
        let (store, _) = makeStore([original])
        try store.startEditing(eventID: original.id)
        XCTAssertEqual(store.saveButtonTitle, "変更を保存")
        XCTAssertEqual(store.mode.headerLabel, "編集中")

        try store.startCopy()
        XCTAssertEqual(store.mode.headerLabel, "コピー中")
        store.selectDay(d2)
        XCTAssertEqual(store.saveButtonTitle, "コピーを保存")
        [d3, d4, CalendarDay(year: 2026, month: 11, day: 9)].forEach(store.selectDay)
        XCTAssertEqual(store.saveButtonTitle, "4件コピー")
    }

    // MARK: - 新規・複数日（仕様 §18・§19・§30）

    func testNewMultipleDaysSavesOneEventPerDay() throws {
        let (store, repository) = makeStore()
        store.startNew()
        [d3, d1, d2].forEach(store.selectDay)
        XCTAssertEqual(store.selectedDays, [d1, d2, d3], "選択日は日付順に並ぶ")
        XCTAssertEqual(store.displayedDay, d2, "最後に選んだ日を表示する")

        store.content.title = "通院"
        store.setStartMinute(14 * 60, on: d1)
        store.setStartMinute(14 * 60 + 30, on: d2)
        store.setStartMinute(9 * 60, on: d3)
        let saved = try store.save()

        XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(repository.allEvents().count, 3)
        XCTAssertEqual(Set(saved.map(\.startMinute)), [840, 870, 540], "日ごとに違う時刻で保存できる")
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testConfirmStartTimeMovesToNextUnsetDay() {
        let (store, _) = makeStore()
        store.startNew()
        [d1, d2, d3].forEach(store.selectDay)
        store.displayDay(d2)
        store.setStartMinute(600)
        XCTAssertEqual(store.confirmStartTime(), d3, "後ろの未設定の日へ移る")
        store.setStartMinute(660)
        XCTAssertEqual(store.confirmStartTime(), d1, "後ろに無ければ前の未設定の日へ戻る")
        store.setStartMinute(720)
        XCTAssertNil(store.confirmStartTime(), "全部決まったら移らない")
        XCTAssertEqual(store.displayedDay, d1)
    }

    func testValidationListsDaysWithoutStartTime() {
        let (store, _) = makeStore()
        store.startNew()
        XCTAssertEqual(store.dateValidation, .noDaySelected)
        [d1, d2].forEach(store.selectDay)
        store.setStartMinute(600, on: d1)
        XCTAssertEqual(store.dateValidation, .missingStartTime([d2]))
        XCTAssertThrowsError(try store.save())
    }

    func testDeselectingDisplayedDayShowsFirstRemainingDay() {
        let (store, _) = makeStore()
        store.startNew()
        [d1, d2, d3].forEach(store.selectDay)
        store.setStartMinute(600, on: d3)
        store.deselectDay(d3)
        XCTAssertEqual(store.selectedDays, [d1, d2])
        XCTAssertEqual(store.displayedDay, d1)
        XCTAssertNil(store.startMinutes[d3], "外した日の時刻も消える")
    }

    func testDraftEventsReflectInputImmediately() {
        let (store, _) = makeStore()
        store.startNew(on: d1)
        store.setStartMinute(870)
        store.content.title = "A社打合せ"
        XCTAssertEqual(store.draftEvents.first?.content.title, "A社打合せ", "入力欄の変更は仮予定に即反映（仕様 §22）")
        XCTAssertEqual(store.draftEvents.first?.startMinute, 870)
    }

    // MARK: - 終了時刻（仕様 §24・§45）

    func testEndMinuteIsOptionalAndMustBeAfterStart() {
        let (store, _) = makeStore()
        store.startNew(on: d1)
        store.setStartMinute(600)
        XCTAssertNil(store.endMinute(on: d1), "何もしなければ終了は未設定")
        store.setEndMinute(570)
        XCTAssertNil(store.content.durationMinutes, "開始より前の終了は入らない")
        store.setEndMinute(690)
        XCTAssertEqual(store.endMinute(on: d1), 690)
        store.setStartMinute(660)
        XCTAssertEqual(store.endMinute(on: d1), 750, "開始を動かすと所要時間を保ったまま終了も動く")
        store.setEndMinute(nil)
        XCTAssertNil(store.endMinute(on: d1))
    }

    // MARK: - 編集（仕様 §25・§31）

    func testEditingAnotherDayMovesTheEvent() throws {
        let original = makeEvent("A社打合せ", on: d1, at: 600)
        let (store, repository) = makeStore([original])
        try store.startEditing(eventID: original.id)
        XCTAssertTrue(store.timedEvents(on: d1).isEmpty, "編集中の予定は保存済みの一覧から外して仮予定として出す")

        store.selectDay(d2)
        XCTAssertEqual(store.selectedDays, [d2], "編集は 1 日だけ")
        XCTAssertEqual(store.startMinutes[d2], 600, "移動しても時刻は保つ")
        XCTAssertTrue(store.hasUnsavedChanges)

        try store.save()
        let events = repository.allEvents()
        XCTAssertEqual(events.count, 1, "移動であって複製ではない")
        XCTAssertEqual(events.first?.id, original.id)
        XCTAssertEqual(events.first?.day, d2)
    }

    // MARK: - コピー（仕様 §32・§33）

    func testCopyKeepsContentButNotDateTimeOrRepeat() throws {
        var original = makeEvent("A社打合せ", on: d1, at: 600, duration: 60)
        original.content.locationName = "広島市中区"
        original.content.color = .mint
        original.content.arrivalTargetMinutes = 10
        original.content.transport = .car
        original.content.memo = "資料を持参"
        let (store, repository) = makeStore([original])

        try store.startEditing(eventID: original.id)
        try store.startCopy()
        XCTAssertTrue(store.selectedDays.isEmpty, "日付は引き継がない")
        XCTAssertTrue(store.startMinutes.isEmpty, "開始時刻は引き継がない")
        XCTAssertEqual(store.content.repeatRule, .none)

        [d2, d3].forEach(store.selectDay)
        store.setStartMinute(540, on: d2)
        store.setStartMinute(780, on: d3)
        let copies = try store.save()

        XCTAssertEqual(copies.count, 2)
        for copy in copies {
            XCTAssertNotEqual(copy.id, original.id)
            XCTAssertEqual(copy.content.title, "A社打合せ")
            XCTAssertEqual(copy.content.locationName, "広島市中区")
            XCTAssertEqual(copy.content.color, .mint)
            XCTAssertEqual(copy.content.arrivalTargetMinutes, 10)
            XCTAssertEqual(copy.content.transport, .car)
            XCTAssertEqual(copy.content.durationMinutes, 60)
            XCTAssertEqual(copy.content.memo, "資料を持参")
        }
        XCTAssertEqual(repository.allEvents().first(where: { $0.id == original.id }), original, "元の予定は変えない")
    }

    func testCopyRequiresEditMode() {
        let (store, _) = makeStore()
        store.startNew(on: d1)
        XCTAssertThrowsError(try store.startCopy())
    }

    // MARK: - 未保存の変更（仕様 §36）

    func testUnsavedChangesAndDiscard() throws {
        let original = makeEvent("A社打合せ", on: d1, at: 600)
        let (store, _) = makeStore([original])
        try store.startEditing(eventID: original.id)
        XCTAssertFalse(store.hasUnsavedChanges)
        store.content.title = "B社打合せ"
        XCTAssertTrue(store.hasUnsavedChanges)
        store.discardChanges()
        XCTAssertEqual(store.content.title, "A社打合せ")
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    // MARK: - 予測で一括（仕様 §19。アルゴリズムはモック）

    func testPredictionFillsOnlyUnsetDaysAndDoesNotSave() {
        let history = [
            makeEvent("A社打合せ", on: CalendarDay(year: 2026, month: 9, day: 1), at: 570),
            makeEvent("A社打合せ", on: CalendarDay(year: 2026, month: 9, day: 8), at: 570),
            makeEvent("A社打合せ", on: CalendarDay(year: 2026, month: 9, day: 15), at: 600),
        ]
        let (store, repository) = makeStore(history)
        store.startNew()
        [d1, d2, d3].forEach(store.selectDay)
        store.content.title = "A社打合せ"
        store.setStartMinute(660, on: d1)

        store.applyPrediction()
        XCTAssertEqual(store.predictionState, .applied([d2, d3]))
        XCTAssertEqual(store.startMinutes[d1], 660, "自分で入れた時刻は変えない")
        XCTAssertEqual(store.startMinutes[d2], 570)
        XCTAssertEqual(repository.allEvents().count, 3, "予測しただけでは保存しない")
    }

    func testPredictionWithoutHistory() {
        let (store, _) = makeStore()
        store.startNew(on: d1)
        store.content.title = "初めての予定"
        store.applyPrediction()
        XCTAssertEqual(store.predictionState, .noSuggestion)
    }

    // MARK: - 時間画面の表示

    func testTimedEventsExcludeAllDayAndAreSorted() {
        let (store, _) = makeStore([
            makeEvent("午後", on: d1, at: 900),
            makeEvent("終日", on: d1, at: 0, allDay: true),
            makeEvent("朝", on: d1, at: 540),
        ])
        XCTAssertEqual(store.timedEvents(on: d1).map(\.content.title), ["朝", "午後"])
        XCTAssertEqual(store.allDayEvents(on: d1).map(\.content.title), ["終日"])
        XCTAssertEqual(store.suggestedScrollMinute(for: d1), 510, "最初の予定の少し前（仕様 §26）")
        XCTAssertNil(store.suggestedScrollMinute(for: d2))
    }
}
