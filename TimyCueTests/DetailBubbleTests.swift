import XCTest
@testable import TimyCue

@MainActor
final class DetailBubbleTests: XCTestCase {
    private let today = CalendarDay(year: 2026, month: 10, day: 12)

    private func makeStores(_ events: [CalendarEvent]) -> (CalendarStore, ScheduleEditorStore) {
        let repository = InMemoryEventRepository(events: events)
        let metadata = InMemoryEventMetadataRepository()
        return (CalendarStore(repository: repository, metadataRepository: metadata, today: today),
                ScheduleEditorStore(repository: repository, metadataRepository: metadata))
    }

    func testMonthPopoverSwitchesBetweenListAndDetail() {
        let event = CalendarEvent(day: today, startMinute: 600, title: "A社")
        let (store, _) = makeStores([event])
        store.tapDay(today)
        XCTAssertNil(store.detailEventID(inPopoverOf: today), "最初は予定一覧")

        store.showDetail(in: today, eventID: event.id)
        XCTAssertEqual(store.detailEventID(inPopoverOf: today), event.id, "同じ吹き出しの中身を予定詳細に切り替える（Q28(a)）")
        XCTAssertEqual(store.openDays, [today], "別の吹き出しは重ねない")

        store.backToList(in: today)
        XCTAssertNil(store.detailEventID(inPopoverOf: today), "詳細の中をもう一度押すと一覧へ戻る（Q29）")
    }

    func testTappingOutsideClosesEverythingWithoutGoingBackToList() {
        let event = CalendarEvent(day: today, startMinute: 600, title: "A社")
        let (store, _) = makeStores([event])
        store.tapDay(today)
        store.showDetail(in: today, eventID: event.id)
        store.closeAllPopovers()
        XCTAssertTrue(store.openDays.isEmpty, "外を押すと一覧へ戻さず、吹き出し全体を閉じる（Q29）")
        store.tapDay(today)
        XCTAssertNil(store.detailEventID(inPopoverOf: today), "次に開いたときは一覧から")
    }

    func testClosingOrReplacingPopoverForgetsItsDetail() {
        let event = CalendarEvent(day: today, startMinute: 600, title: "A社")
        let (store, _) = makeStores([event])
        store.tapDay(today)
        store.showDetail(in: today, eventID: event.id)
        store.tapDay(today.adding(days: 1))
        store.tapDay(today.adding(days: 2))
        XCTAssertFalse(store.isOpen(today), "3 つ目で古い吹き出しが閉じる")
        store.tapDay(today)
        XCTAssertNil(store.detailEventID(inPopoverOf: today))
    }

    func testEditFromBubbleOpensEditorAndKeepsBubble() {
        let event = CalendarEvent(day: today, startMinute: 600, title: "A社")
        let (store, editor) = makeStores([event])
        store.tapDay(today)
        store.showDetail(in: today, eventID: event.id)

        editor.beginEditing(event.id, from: store)
        XCTAssertEqual(store.editRequest, EditRequest(id: event.id, month: CalendarMonth(today)), "「編集」で 3 分割画面を開く（Q30）")
        XCTAssertEqual(editor.mode, .edit(eventID: event.id))

        store.editRequest = nil
        XCTAssertEqual(store.detailEventID(inPopoverOf: today), event.id, "閉じたら予定詳細の吹き出しをそのまま出す（Q30）")
    }

    func testDeletingClosesDetail() {
        let event = CalendarEvent(day: today, startMinute: 600, title: "A社")
        let (store, _) = makeStores([event])
        store.tapDay(today)
        store.showDetail(in: today, eventID: event.id)
        store.openTimeline(today)
        store.tapTimelineEvent(event.id)
        store.closeEventDetail(event.id)
        XCTAssertNil(store.detailEventID(inPopoverOf: today), "消した予定の詳細は一覧に戻す")
        XCTAssertNil(store.timelineDetailEventID)
    }

    func testTappingSameBlockAgainClosesDetail() {
        let event = CalendarEvent(day: today, startMinute: 600, title: "A社")
        let (store, _) = makeStores([event])
        store.tapTimelineEvent(event.id)
        store.tapTimelineEvent(event.id)
        XCTAssertNil(store.timelineDetailEventID)
    }

    func testPlacementGoesSidewaysWhenAboveAndBelowAreFull() {
        // 縦に長い予定ブロック：上にも下にも入らない → 横に出す。ブロックは隠さない（Q28(b)）
        let block = CGRect(x: 60, y: 40, width: 120, height: 700)
        let frame = PopoverPlacement.frames(container: CGSize(width: 440, height: 800),
                                            anchors: [block],
                                            sizes: [CGSize(width: 240, height: 230)],
                                            gap: 4, margin: 8)[0]
        XCTAssertFalse(frame.intersects(block), "予定ブロックを隠さない")
        XCTAssertEqual(frame.minX, block.maxX + 4, "右に空きがあれば右")
        XCTAssertTrue(frame.minY >= 8 && frame.maxY <= 792)
    }
}
