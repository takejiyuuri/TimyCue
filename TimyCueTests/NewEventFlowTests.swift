import XCTest
@testable import TimyCue

@MainActor
final class NewEventFlowTests: XCTestCase {
    private let today = CalendarDay(year: 2026, month: 10, day: 12)

    private func makeCalendarStore(_ events: [CalendarEvent] = []) -> CalendarStore {
        CalendarStore(repository: InMemoryEventRepository(events: events),
                      metadataRepository: InMemoryEventMetadataRepository(),
                      today: today)
    }

    func testMonthPlusStartsOnSelectedDayOrToday() {
        let store = makeCalendarStore()
        XCTAssertEqual(store.dayForNewEvent, today, "選んでいる日がなければ今日（Q21）")
        store.tapDay(today.adding(days: 3))
        store.tapDay(today.adding(days: 5))
        XCTAssertEqual(store.dayForNewEvent, today.adding(days: 5), "選んでいる日（いちばん新しく開いた吹き出しの日）")
    }

    func testAfterSavingFromMonthTheSavedDayIsOpened() {
        let store = makeCalendarStore()
        let saved = today.adding(days: 7)
        store.showSavedDay(saved)
        XCTAssertTrue(store.isOpen(saved), "保存した日の吹き出しを開く（Q22）")
        store.showSavedDay(saved)
        XCTAssertTrue(store.isOpen(saved), "もう開いていれば閉じない")
    }

    func testAfterSavingFromTimelineItScrollsToTheEvent() {
        let store = makeCalendarStore()
        store.focusTimeline(on: today, minute: 14 * 60)
        XCTAssertEqual(store.timelineFocus, TimelineFocus(day: today, minute: 14 * 60), "作った予定の時刻へ（Q22）")
        store.clearTimelineFocus()
        XCTAssertNil(store.timelineFocus)
    }

    func testNewEventFromPlusHasNoStartTime() {
        let editor = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository())
        editor.startNew(on: today)
        XCTAssertEqual(editor.selectedDays, [today])
        XCTAssertNil(editor.startMinutes[today], "開始時刻は未設定（Q21）")
    }

    func testEditorCalendarDots() throws {
        let events = (0..<5).map { CalendarEvent(day: today, startMinute: 600 + $0 * 60, title: "予定\($0)") }
            + [CalendarEvent(day: today, startMinute: 0, title: "終日", isAllDay: true)]
        var metadata: [UUID: TimyCueEventMetadata] = [:]
        var allDayInfo = TimyCueEventMetadata()
        allDayInfo.color = .mint
        metadata[events.last!.id] = allDayInfo
        let editor = ScheduleEditorStore(repository: InMemoryEventRepository(events: events),
                                         metadataRepository: InMemoryEventMetadataRepository(metadata: metadata))
        let dots = editor.eventDots(on: today)
        XCTAssertEqual(dots.colors.count, 3, "ドットは最大 3 個（Q23）")
        XCTAssertEqual(dots.colors.first, .mint, "終日が先頭")
        XCTAssertEqual(dots.more, 3, "残りは +3")
        XCTAssertEqual(editor.eventDots(on: today.adding(days: 1)).colors, [])
        XCTAssertEqual(editor.eventDots(on: today.adding(days: 1)).more, 0)
    }

    func testEndIsSetWithTheHandle() {
        let editor = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository())
        editor.startNew(on: today)
        editor.setStartMinute(600)
        editor.setEndMinute(675)
        XCTAssertEqual(editor.durationMinutes(on: today), 75, "終了は下端のハンドルで決める（「終了」の行はなくした。2026-10-14）")
        XCTAssertEqual(editor.endMinute(on: today), 675)
    }
}
