import XCTest
@testable import TimyCue

/// 日付が変わったときの吹き出し（2026-10-17 決定 Q96）。開いたときにその日が今日だった吹き出し（前の日の「今日」）は、
/// 自動で開いたか手で押したかに依らず閉じる。開いたときに別の日だった吹き出し（手で選んだ別の日・日付が変わってから選んだ過去の日）は残す。
/// 今日の吹き出しは開き直さない。［＋］の初めの日は Q21 のまま（開いている吹き出しの日、なければ今日）。作成・編集中の中身と日は変えない
@MainActor
final class DayChangePopoverTests: XCTestCase {
    private let yesterday = CalendarDay(year: 2026, month: 10, day: 16)
    private var today: CalendarDay { yesterday.adding(days: 1) }

    private func makeStore(today: CalendarDay) -> CalendarStore {
        CalendarStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository(), today: today)
    }

    // 1. 自動で開いた今日の吹き出しは、日付が変わったら閉じる
    func testTodayOpenedAutomaticallyClosesWhenTheDayChanges() {
        let byTodayButton = makeStore(today: yesterday)
        byTodayButton.scrollToToday()
        XCTAssertEqual(byTodayButton.openDays, [yesterday], "「今日」で今日の吹き出しを開く")
        byTodayButton.updateToday(today)
        XCTAssertEqual(byTodayButton.openDays, [], "前の日の「今日」の吹き出しを閉じる")

        let afterSaving = makeStore(today: yesterday)
        afterSaving.showSavedDay(yesterday)
        afterSaving.updateToday(today)
        XCTAssertEqual(afterSaving.openDays, [], "今日の予定を保存して開いた吹き出しも閉じる")
    }

    // 2. 手で開いた今日の吹き出しも閉じる
    func testTodayOpenedByHandAlsoCloses() {
        let store = makeStore(today: yesterday)
        store.tapDay(yesterday)
        store.updateToday(today)
        XCTAssertEqual(store.openDays, [], "手で押して開いた前の日の「今日」も閉じる（［＋］が前の日から始まらない）")
        XCTAssertEqual(store.dayForNewEvent, today)
    }

    // 3. 別の日を手で選んでいた場合は残す
    func testAnotherDayChosenBeforeTheChangeStays() {
        let store = makeStore(today: yesterday)
        let past = yesterday.adding(days: -3)
        let future = yesterday.adding(days: 5)
        store.tapDay(past)
        store.tapDay(future)
        store.updateToday(today)
        XCTAssertEqual(store.openDays, [past, future], "開いたときに今日でなかった日は変えない")
        XCTAssertEqual(store.dayForNewEvent, future, "［＋］は Q21 どおり、いちばん新しく開いた日から")

        let saved = makeStore(today: yesterday)
        saved.showSavedDay(future)
        saved.updateToday(today)
        XCTAssertEqual(saved.openDays, [future], "ほかの日の予定を保存して開いた吹き出しも残す")
    }

    // 4. 日付が変わってから過去の日を選び直した場合は閉じない
    func testAPastDayChosenAfterTheChangeStays() {
        let store = makeStore(today: yesterday)
        store.tapDay(yesterday)
        store.updateToday(today)
        XCTAssertEqual(store.openDays, [])
        store.tapDay(yesterday)
        XCTAssertEqual(store.dayForNewEvent, yesterday, "過去の日を選んで登録することはできる")
        store.updateToday(today.adding(days: 1))
        XCTAssertEqual(store.openDays, [yesterday], "選んだときに今日でなかったので、次に日付が変わっても閉じない")
    }

    // 5. 予定の作成・編集中は内容と日を変えない
    func testAnEventBeingEditedKeepsItsDayAndContent() {
        let store = makeStore(today: yesterday)
        let editor = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository())
        store.tapDay(yesterday)
        editor.startNew(on: store.dayForNewEvent)
        editor.setStartMinute(19 * 60 + 35)
        XCTAssertTrue(editor.hasUnsavedChanges)
        store.updateToday(today)
        XCTAssertEqual(editor.selectedDays, [yesterday], "作成中の予定の日は変えない（画面の上で変えるのは利用者）")
        XCTAssertEqual(editor.startMinutes[yesterday], 19 * 60 + 35, "入力した開始時刻もそのまま")
        XCTAssertTrue(editor.hasUnsavedChanges, "入力途中のまま")
        XCTAssertEqual(store.openDays, [], "うしろのカレンダーの前の日の「今日」の吹き出しだけを閉じる")
    }

    func testEditingFromTheDetailBubbleKeepsTheEditorOpen() {
        let event = CalendarEvent(day: yesterday, startMinute: 600, title: "A社")
        let repository = InMemoryEventRepository(events: [event])
        let metadata = InMemoryEventMetadataRepository()
        let store = CalendarStore(repository: repository, metadataRepository: metadata, today: yesterday)
        let editor = ScheduleEditorStore(repository: repository, metadataRepository: metadata)
        store.tapDay(yesterday)
        store.showDetail(in: yesterday, eventID: event.id)
        editor.beginEditing(event.id, from: store)
        editor.setStartMinute(19 * 60 + 35, on: yesterday)
        let request = store.editRequest
        XCTAssertNotNil(request, "予定詳細の「編集」で 3 分割画面を開く（Q30）")

        store.updateToday(today)
        XCTAssertEqual(store.editRequest, request, "編集の画面は閉じない")
        XCTAssertEqual(editor.mode, .edit(eventID: event.id))
        XCTAssertEqual(editor.selectedDays, [yesterday], "編集中の予定の日は変えない")
        XCTAssertEqual(editor.startMinutes[yesterday], 19 * 60 + 35, "入力した開始時刻もそのまま")
        XCTAssertTrue(editor.hasUnsavedChanges)
        XCTAssertEqual(store.openDays, [], "うしろの前の日の「今日」の吹き出しは閉じる")
        XCTAssertNil(store.detailEventID(inPopoverOf: yesterday), "編集を終えても吹き出しは戻さない（この場合 Q30 の再表示は求めない）")
    }

    // 6. 閉じたあと［＋］が前の日を引き継がない
    func testThePlusButtonDoesNotInheritYesterdayAfterClosing() {
        let store = makeStore(today: yesterday)
        store.scrollToToday()
        store.updateToday(today)
        XCTAssertEqual(store.dayForNewEvent, today, "ほかに開いている吹き出しがなければ今日から")

        let withAnother = makeStore(today: yesterday)
        let chosen = yesterday.adding(days: 2)
        withAnother.tapDay(chosen)
        withAnother.tapDay(yesterday)
        XCTAssertEqual(withAnother.dayForNewEvent, yesterday)
        withAnother.updateToday(today)
        XCTAssertEqual(withAnother.openDays, [chosen])
        XCTAssertEqual(withAnother.dayForNewEvent, chosen, "前の日ではなく、残った吹き出しの日から（Q21）")
    }

    // 7. 日付が変わったとき・前面に戻ったとき（どちらも同じ処理を呼ぶ。日が同じなら何もしない）
    func testRepeatedCallsOnTheSameDayChangeNothingAndTwoDaysLaterStillCloses() {
        let store = makeStore(today: yesterday)
        store.tapDay(yesterday)
        store.updateToday(yesterday)
        XCTAssertEqual(store.openDays, [yesterday], "日が同じなら何もしない（前面に戻すたびに呼ばれる）")
        store.updateToday(today.adding(days: 1))
        XCTAssertEqual(store.openDays, [], "2 日たってから前面に戻しても閉じる")
        store.updateToday(today.adding(days: 1))
        XCTAssertEqual(store.openDays, [])
    }

    func testTodayOpenedAgainAfterClosingIsStillToday() {
        let store = makeStore(today: yesterday)
        store.scrollToToday()
        store.tapDay(yesterday)
        XCTAssertEqual(store.openDays, [], "開いている日を押すと閉じる（Q9）")
        store.tapDay(yesterday)
        store.updateToday(today)
        XCTAssertEqual(store.openDays, [], "押して開き直しても、そのとき今日なら日付が変わったら閉じる")
    }
}
