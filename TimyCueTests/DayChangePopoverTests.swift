import XCTest
@testable import TimyCue

/// 日付が変わったときの吹き出し（2026-10-17 決定 Q96）。前の日に自動で開いていた「今日」の吹き出しだけを閉じ、
/// 手で選んだ日・作成中の予定は変えない。［＋］の初めの日は Q21 のまま（開いている吹き出しの日、なければ今日）
@MainActor
final class DayChangePopoverTests: XCTestCase {
    private let yesterday = CalendarDay(year: 2026, month: 10, day: 16)
    private var today: CalendarDay { yesterday.adding(days: 1) }

    private func makeStore(today: CalendarDay) -> CalendarStore {
        CalendarStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository(), today: today)
    }

    func testTodayOpenedByTheTodayButtonClosesWhenTheDayChanges() {
        let store = makeStore(today: yesterday)
        store.scrollToToday()
        XCTAssertEqual(store.openDays, [yesterday], "「今日」で今日の吹き出しを自動で開く")
        store.updateToday(today)
        XCTAssertEqual(store.openDays, [], "日付が変わったら、前の日の「今日」の吹き出しを閉じる")
        XCTAssertEqual(store.dayForNewEvent, today, "［＋］は今日から")
    }

    func testTodayOpenedAfterSavingClosesButAnotherSavedDayStays() {
        let store = makeStore(today: yesterday)
        store.showSavedDay(yesterday)
        store.updateToday(today)
        XCTAssertEqual(store.openDays, [], "今日の予定を保存して自動で開いた吹き出しは閉じる")

        let other = makeStore(today: yesterday)
        let chosen = yesterday.adding(days: 5)
        other.showSavedDay(chosen)
        other.updateToday(today)
        XCTAssertEqual(other.openDays, [chosen], "編集画面で選んだほかの日の吹き出しは残す")
        XCTAssertEqual(other.dayForNewEvent, chosen, "［＋］は Q21 どおり開いている日から")
    }

    func testDaysChosenByHandAreKeptEvenIfTheyWereToday() {
        let store = makeStore(today: yesterday)
        let past = yesterday.adding(days: -3)
        store.tapDay(past)
        store.updateToday(today)
        XCTAssertEqual(store.openDays, [past], "手で選んだ別の日は今日へ変えない")
        XCTAssertEqual(store.dayForNewEvent, past, "過去の日を手で選んで登録することもできる")

        let byHand = makeStore(today: yesterday)
        byHand.tapDay(yesterday)
        byHand.updateToday(today)
        XCTAssertEqual(byHand.openDays, [yesterday], "その日が今日だったときでも、手で押して開いたものは閉じない")
    }

    func testTappingAnAutomaticTodayMakesItAChoiceByHand() {
        let store = makeStore(today: yesterday)
        store.scrollToToday()
        store.tapDay(yesterday)
        XCTAssertEqual(store.openDays, [], "自動で開いた吹き出しを押すと閉じる（Q9）")
        store.tapDay(yesterday)
        store.updateToday(today)
        XCTAssertEqual(store.openDays, [yesterday], "押して開き直したものは手で選んだ日として残す")
    }

    func testOnlyTheAutomaticTodayClosesWhenTwoPopoversAreOpen() {
        let store = makeStore(today: yesterday)
        store.scrollToToday()
        let chosen = yesterday.adding(days: 2)
        store.tapDay(chosen)
        XCTAssertEqual(store.openDays, [yesterday, chosen])
        store.updateToday(today)
        XCTAssertEqual(store.openDays, [chosen], "手で選んだ方は残す")
    }

    func testNothingChangesOnTheSameDayOrWithoutPopovers() {
        let store = makeStore(today: yesterday)
        store.scrollToToday()
        store.updateToday(yesterday)
        XCTAssertEqual(store.openDays, [yesterday], "日が同じなら何もしない（前面に戻すたびに呼ばれる）")

        let empty = makeStore(today: yesterday)
        empty.updateToday(today)
        XCTAssertEqual(empty.openDays, [])
        XCTAssertEqual(empty.dayForNewEvent, today)
    }

    func testAnEventBeingEditedKeepsItsDayAndContent() {
        let store = makeStore(today: yesterday)
        let editor = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository())
        store.scrollToToday()
        editor.startNew(on: store.dayForNewEvent)
        editor.setStartMinute(19 * 60 + 35)
        XCTAssertTrue(editor.hasUnsavedChanges)
        store.updateToday(today)
        XCTAssertEqual(editor.selectedDays, [yesterday], "作成中の予定の日は変えない（画面の上で変えるのは利用者）")
        XCTAssertEqual(editor.startMinutes[yesterday], 19 * 60 + 35, "入力した開始時刻もそのまま")
        XCTAssertTrue(editor.hasUnsavedChanges, "入力途中のまま")
        XCTAssertEqual(store.openDays, [], "うしろのカレンダーの吹き出しだけを閉じる")
    }
}
