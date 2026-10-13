import XCTest
@testable import TimyCue

/// Apple カレンダーの予定の編集（追加仕様書 §1.7：編集できない予定、§1.12：ローカル予定を Apple カレンダーへ移す）
final class AppleCalendarEditingTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 12)
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .orange)
    private let holidays = CalendarChoice(id: "jp", title: "日本の祝日", sourceTitle: "購読", isWritable: false, color: .green)

    @MainActor
    func testReadOnlyCalendarLocksAppleFieldsButKeepsTimyCueSettingsEditable() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "共有の会議", source: .appleCalendar, calendarID: "jp")
        let repository = InMemoryEventRepository(events: [event])
        let metadata = InMemoryEventMetadataRepository()
        let store = ScheduleEditorStore(repository: repository, metadataRepository: metadata)
        store.setCalendars([home, holidays], defaultCalendarID: "home")
        XCTAssertEqual(store.writableCalendars, [home], "保存先に選べるのは書き込めるカレンダーだけ")

        try store.startEditing(eventID: event.id)
        XCTAssertTrue(store.areAppleFieldsLocked)
        XCTAssertNotNil(store.appleFieldsLockReason, "ロックの短い理由を出す")
        XCTAssertTrue(store.isLocked(.title))
        XCTAssertTrue(store.isLocked(.location))
        XCTAssertFalse(store.isLocked(.arrivalTarget), "TimyCue の設定は変えられる")
        XCTAssertFalse(store.isLocked(.color))

        store.toggleRow(.title)
        XCTAssertNil(store.expandedRow, "ロックした行は開かない")
        store.toggleRow(.arrivalTarget)
        XCTAssertEqual(store.expandedRow, .arrivalTarget)

        store.setStartMinute(720)
        XCTAssertEqual(store.startMinutes[day], 600, "日時は動かせない")
        store.selectDay(day.adding(days: 1))
        XCTAssertEqual(store.selectedDays, [day])

        store.content.title = "書き換え"
        store.content.metadata.arrivalTargetMinutes = 25
        try store.save()
        XCTAssertEqual(repository.allEvents().first?.title, "共有の会議", "Apple カレンダーへは書かない")
        XCTAssertEqual(metadata.allMetadata()[event.id]?.arrivalTargetMinutes, 25, "TimyCue の設定だけ保存する")
    }

    @MainActor
    func testWritableCalendarIsNotLocked() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar, calendarID: "home")
        let store = ScheduleEditorStore(repository: InMemoryEventRepository(events: [event]),
                                        metadataRepository: InMemoryEventMetadataRepository())
        store.setCalendars([home, holidays], defaultCalendarID: "home")
        try store.startEditing(eventID: event.id)
        XCTAssertFalse(store.areAppleFieldsLocked)
        XCTAssertFalse(store.isLocked(.title))
    }

    // MARK: - 祝日など見るだけの予定（2026-10-13 ユーザー決定）

    func testHolidaysAreViewOnly() {
        let readOnly: Set<String> = ["jp"]
        let holiday = CalendarEvent(day: day, startMinute: 0, title: "スポーツの日", isAllDay: true,
                                    source: .appleCalendar, calendarID: "jp")
        XCTAssertTrue(CalendarStore.isViewOnly(holiday, readOnlyCalendarIDs: readOnly),
                      "祝日は編集画面を出さず、吹き出しで何の日か分かればよい")
        let timedShared = CalendarEvent(day: day, startMinute: 600, title: "共有の会議", source: .appleCalendar, calendarID: "jp")
        XCTAssertFalse(CalendarStore.isViewOnly(timedShared, readOnlyCalendarIDs: readOnly),
                       "時間指定の予定は、書き込めないカレンダーでも TimyCue の設定を変えられる（§1.7）")
        let ownAllDay = CalendarEvent(day: day, startMinute: 0, title: "休み", isAllDay: true, source: .appleCalendar, calendarID: "home")
        XCTAssertFalse(CalendarStore.isViewOnly(ownAllDay, readOnlyCalendarIDs: readOnly), "自分のカレンダーの終日予定は編集できる")
    }

    // MARK: - ローカル予定を Apple カレンダーへ移す（§1.12）

    @MainActor
    func testMovingLocalEventToAppleCalendarCarriesSettingsAndRemovesTheLocalOne() throws {
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let local = InMemoryEventRepository(events: [localEvent])
        let apple = InMemoryEventRepository()
        let metadata = InMemoryEventMetadataRepository()
        var settings = TimyCueEventMetadata()
        settings.arrivalTargetMinutes = 10
        settings.transport = .walk
        try metadata.save(settings, for: localEvent.id)
        let store = ScheduleEditorStore(repository: CombinedEventRepository(primary: apple, local: local),
                                        metadataRepository: metadata)

        try store.startEditing(eventID: localEvent.id)
        XCTAssertFalse(store.canMoveToAppleCalendar, "つないでいないときは出さない")
        store.setCalendars([home], defaultCalendarID: "home")
        XCTAssertTrue(store.canMoveToAppleCalendar, "つないだあとも、自動では移さず、編集画面で選んだときだけ")

        store.content.metadata.arrivalTargetMinutes = 20
        let moved = try store.moveToAppleCalendar()
        XCTAssertTrue(local.allEvents().isEmpty, "元のローカル予定は消す（二重に出さない）")
        XCTAssertEqual(apple.allEvents().map(\.title), ["歯医者"], "Apple カレンダーに新しく作る")
        XCTAssertEqual(metadata.allMetadata()[moved.id]?.arrivalTargetMinutes, 20, "TimyCue の設定を引き継ぐ")
        XCTAssertEqual(metadata.allMetadata()[moved.id]?.transport, .walk)
        XCTAssertNil(metadata.allMetadata()[localEvent.id])
        XCTAssertEqual(store.mode, .edit(eventID: moved.id), "移した予定に紐づけ替える")
        XCTAssertFalse(store.canMoveToAppleCalendar)
    }
}
