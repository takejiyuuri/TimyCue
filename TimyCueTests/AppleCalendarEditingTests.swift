import XCTest
@testable import TimyCue

/// Apple カレンダーの予定の編集（追加仕様書 §1.7：編集できない予定）
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
}
