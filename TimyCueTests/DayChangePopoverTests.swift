import XCTest
@testable import TimyCue

/// 日付が変わったときの吹き出し（2026-10-17 決定 Q96）。開いたときにその日が今日だった吹き出し（前の日の「今日」）は、
/// 自動で開いたか手で押したかに依らず閉じる。開いたときに別の日だった吹き出し（手で選んだ別の日・日付が変わってから選んだ過去の日）は残す。
/// 今日の吹き出しは開き直さない。［＋］の初めの日は Q21 のまま（開いている吹き出しの日、なければ今日）。作成・編集中の中身と日は変えず、
/// 下のカレンダーの「今日」の淡い印だけを動かす。0 時をまたいで前の日のまま保存したら、前の日の予定として保存し、その日の吹き出しを出す（Q22）
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

    // 作成・編集の画面の下のカレンダー：日付が変わったら「今日」の淡い印だけが動く（2026-10-17 決定）。
    // 画面を開いたまま 0 時をまたいだときも、裏へ回して翌日に前面へ戻したときも、同じ処理（updateToday）を呼ぶ
    func testEditorTodayMarkMovesButTheChosenDayAndInputStay() {
        let store = makeStore(today: yesterday)
        let editor = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository())
        let chosen = yesterday.adding(days: 3)
        editor.startNew(on: chosen)
        editor.content.title = "見本の打合せ"
        editor.setStartMinute(14 * 60)
        let days = [yesterday, today, chosen]
        let before = days.map { editor.calendarMarks(on: $0, today: store.today) }
        XCTAssertEqual(before.map(\.isToday), [true, false, false])

        store.updateToday(today)
        let after = days.map { editor.calendarMarks(on: $0, today: store.today) }
        XCTAssertEqual(after.map(\.isToday), [false, true, false], "今日の淡い丸だけが新しい今日へ動く")
        XCTAssertEqual(after.map(\.isSelected), before.map(\.isSelected), "選んだ日は変えない")
        XCTAssertEqual(after.map(\.isDisplayed), before.map(\.isDisplayed), "左上（時間画面）の日も変えない")
        XCTAssertEqual(editor.selectedDays, [chosen])
        XCTAssertEqual(editor.displayedDay, chosen)
        XCTAssertEqual(editor.content.title, "見本の打合せ", "入力した予定名もそのまま")
        XCTAssertEqual(editor.startMinutes[chosen], 14 * 60)
        XCTAssertTrue(editor.hasUnsavedChanges)
    }

    func testEditorOpenedOnTodayKeepsThatDayAfterComingBackTheNextDay() {
        let store = makeStore(today: yesterday)
        let editor = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository())
        editor.startNew(on: store.dayForNewEvent)
        editor.content.title = "見本の打合せ"
        editor.setStartMinute(23 * 60 + 30)

        store.updateToday(today)
        XCTAssertEqual(editor.calendarMarks(on: yesterday, today: store.today),
                       EditorDayMarks(isSelected: true, isDisplayed: true, isCopySource: false, isToday: false),
                       "作っている日（前の日）は選んだまま。今日の印だけが外れる")
        XCTAssertEqual(editor.calendarMarks(on: today, today: store.today),
                       EditorDayMarks(isSelected: false, isDisplayed: false, isCopySource: false, isToday: true),
                       "新しい今日には印だけが付き、選ばれはしない")
        XCTAssertEqual(editor.selectedDays, [yesterday], "対象の日を今日へ変えない")
        XCTAssertEqual(editor.startMinutes[yesterday], 23 * 60 + 30)
    }

    // 0 時をまたいで、前の日のまま保存した（Q22・Q96。2026-10-17 決定）：前の日の予定として保存し、前の日の吹き出しを出す。
    // その吹き出しは、日付が変わってから開いた過去の日として扱い、自動では閉じない
    func testSavingYesterdayAfterMidnightKeepsItsDayAndShowsItsPopover() throws {
        let repository = InMemoryEventRepository()
        let metadata = InMemoryEventMetadataRepository()
        let store = CalendarStore(repository: repository, metadataRepository: metadata, today: yesterday)
        let editor = ScheduleEditorStore(repository: repository, metadataRepository: metadata)
        editor.startNew(on: store.dayForNewEvent)
        editor.content.title = "見本の打合せ"
        editor.setStartMinute(23 * 60 + 30)
        store.updateToday(today)

        let saved = try editor.save()
        XCTAssertEqual(saved.map(\.day), [yesterday], "前の日の予定として保存する（今日へ変えない・翌日へ移さない）")
        let first = try XCTUnwrap(saved.map(\.day).min())
        store.showSavedDay(first)
        XCTAssertEqual(store.openDays, [yesterday], "保存した前の日の吹き出しを出す（Q22）")
        XCTAssertEqual(store.events(on: yesterday).map(\.title), ["見本の打合せ"])
        XCTAssertTrue(store.events(on: today).isEmpty)
        XCTAssertEqual(DayPopoverView.title(for: first), "10月16日（金）", "吹き出しの見出しは「今日」ではなく日付で出す")

        store.updateToday(today.adding(days: 1))
        XCTAssertEqual(store.openDays, [yesterday], "日付が変わってから開いた過去の日なので、自動では閉じない")
        XCTAssertEqual(store.dayForNewEvent, yesterday, "［＋］は Q21 どおり、開いている吹き出しの日から")
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
