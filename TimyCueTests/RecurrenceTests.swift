import EventKit
import XCTest
@testable import TimyCue

/// 繰り返し予定（Q37・Q44）：決まりの表し方、Apple カレンダーとの変換、範囲を選んで直す・消す
final class RecurrenceTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 12)

    // MARK: - 決まりの表し方

    func testChoicesAndLabels() {
        XCTAssertEqual(RepeatRule.none.choice, .none)
        XCTAssertEqual(RepeatRule.none.displayName, "なし")
        XCTAssertEqual(RepeatRule.daily.displayName, "毎日")
        XCTAssertEqual(RepeatRule.weekly.displayName, "毎週")
        XCTAssertEqual(RepeatRule.biweekly.displayName, "隔週")
        XCTAssertEqual(RepeatRule.monthly.displayName, "毎月")
        XCTAssertEqual(RepeatRule(frequency: .daily, interval: 3).choice, .custom)
        XCTAssertEqual(RepeatRule(frequency: .daily, interval: 3).displayName, "3日ごと")
        XCTAssertEqual(RepeatRule(frequency: .weekly, interval: 2, weekdays: [2, 0]).displayName, "2週ごと（月・水）")
        XCTAssertEqual(RepeatRule(frequency: .monthly, endDay: CalendarDay(year: 2026, month: 11, day: 30)).displayName,
                       "毎月（〜11/30まで）", "終わりの日は選択肢を変えない")
        XCTAssertEqual(RepeatRule(frequency: .weekly, interval: 0).interval, 1, "間隔は 1 以上")
    }

    func testOldFilesWithRepeatNoneStillLoad() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            CalendarEvent(day: day, startMinute: 600, title: "A社"))) as! [String: Any]
        json["repeatRule"] = "none"
        let old = try JSONDecoder().decode(CalendarEvent.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.repeatRule, .none, "繰り返しが「なし」だけだったころのファイルも読める")

        let weekly = CalendarEvent(day: day, startMinute: 600, title: "朝会",
                                   repeatRule: RepeatRule(frequency: .weekly, interval: 2, weekdays: [0, 2]))
        let reloaded = try JSONDecoder().decode(CalendarEvent.self, from: JSONEncoder().encode(weekly))
        XCTAssertEqual(reloaded.repeatRule, weekly.repeatRule)
    }

    // MARK: - Apple カレンダーの繰り返しとの変換（EventKit を正本にする）

    func testConvertsToAndFromEventKit() {
        XCTAssertNil(EventKitRecurrence.rule(from: .none), "なしなら繰り返しを付けない")

        let biweekly = EventKitRecurrence.rule(from: .biweekly)
        XCTAssertEqual(biweekly?.frequency, .weekly)
        XCTAssertEqual(biweekly?.interval, 2)
        XCTAssertEqual(EventKitRecurrence.repeatRule(from: biweekly), .biweekly)

        let custom = RepeatRule(frequency: .weekly, interval: 1, weekdays: [0, 2, 6],
                                endDay: CalendarDay(year: 2026, month: 12, day: 25))
        let ek = EventKitRecurrence.rule(from: custom)
        XCTAssertEqual(Set(ek?.daysOfTheWeek?.map(\.dayOfTheWeek) ?? []), [.monday, .wednesday, .sunday])
        XCTAssertEqual(EventKitRecurrence.repeatRule(from: ek), custom, "曜日と終わりの日も行き来できる")

        XCTAssertEqual(EventKitRecurrence.repeatRule(from: EventKitRecurrence.rule(from: .monthly)), .monthly)
        XCTAssertEqual(EventKitRecurrence.repeatRule(from: nil), .none)
    }

    func testWeekdayNumbers() {
        XCTAssertEqual(EventKitRecurrence.ekWeekday(fromMondayIndex: 0), .monday)
        XCTAssertEqual(EventKitRecurrence.ekWeekday(fromMondayIndex: 5), .saturday)
        XCTAssertEqual(EventKitRecurrence.ekWeekday(fromMondayIndex: 6), .sunday)
        for index in 0..<7 {
            XCTAssertEqual(EventKitRecurrence.mondayIndex(from: EventKitRecurrence.ekWeekday(fromMondayIndex: index)!), index)
        }
    }

    // MARK: - 範囲を選んで直す・消す（Q44）

    @MainActor
    func testEditingRecurringEventAsksScopeAndAppliesTimyCueInfoToTheSeries() throws {
        let first = CalendarEvent(day: day, startMinute: 600, title: "朝会", repeatRule: .weekly, source: .appleCalendar)
        let second = CalendarEvent(day: day.adding(days: 7), startMinute: 600, title: "朝会", repeatRule: .weekly, source: .appleCalendar)
        let repository = ScopeRecordingRepository(events: [first, second])
        let metadata = InMemoryEventMetadataRepository()
        let store = ScheduleEditorStore(repository: repository, metadataRepository: metadata)

        try store.startEditing(eventID: first.id)
        XCTAssertTrue(store.isEditingRecurringEvent, "繰り返し予定は保存のときに範囲を聞く")
        store.content.metadata.arrivalTargetMinutes = 20
        try store.save(scope: .futureEvents)

        XCTAssertEqual(repository.updatedScopes, [.futureEvents], "選んだ範囲で直す")
        XCTAssertEqual(metadata.allMetadata()[first.id]?.arrivalTargetMinutes, 20)
        XCTAssertEqual(metadata.allMetadata()[second.id]?.arrivalTargetMinutes, 20,
                       "「これ以降」なら、同じ繰り返しのあとの回にも TimyCue の情報を当てる")
    }

    @MainActor
    func testNonRecurringEventIsSavedAsThisEvent() throws {
        let single = CalendarEvent(day: day, startMinute: 600, title: "A社")
        let repository = ScopeRecordingRepository(events: [single])
        let store = ScheduleEditorStore(repository: repository, metadataRepository: InMemoryEventMetadataRepository())
        try store.startEditing(eventID: single.id)
        XCTAssertFalse(store.isEditingRecurringEvent)
        try store.save(scope: .allEvents)
        XCTAssertEqual(repository.updatedScopes, [.thisEvent], "繰り返しでない予定は範囲を聞かずにそのまま直す")
    }

    @MainActor
    func testDeletingRecurringEventUsesTheChosenScope() throws {
        let first = CalendarEvent(day: day, startMinute: 600, title: "朝会", repeatRule: .weekly, source: .appleCalendar)
        let repository = ScopeRecordingRepository(events: [first])
        let store = ScheduleEditorStore(repository: repository, metadataRepository: InMemoryEventMetadataRepository())
        try store.startEditing(eventID: first.id)
        try store.deleteEditingEvent(scope: .allEvents)
        XCTAssertEqual(repository.deletedScopes, [.allEvents], "削除も同じ 3 択（§64・Q44）")
    }

    @MainActor
    func testRepeatIsOnlyAvailableWhenConnected() {
        let store = ScheduleEditorStore(repository: InMemoryEventRepository(), metadataRepository: InMemoryEventMetadataRepository())
        XCTAssertFalse(store.canRepeat, "連携していないときは繰り返しを選べない（EventKit が正本。Q48 は仮）")
        store.setCalendars([CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .orange)],
                           defaultCalendarID: "home")
        XCTAssertTrue(store.canRepeat)
    }
}

/// 範囲つきの変更・削除を記録するだけの保存先（テスト用）。同じ予定名の予定を、同じ繰り返しの回とみなす
private final class ScopeRecordingRepository: EventRepository {
    private var events: [CalendarEvent]
    private(set) var updatedScopes: [RecurrenceScope] = []
    private(set) var deletedScopes: [RecurrenceScope] = []

    init(events: [CalendarEvent]) {
        self.events = events
    }

    func allEvents() -> [CalendarEvent] { events }
    func insert(_ newEvents: [CalendarEvent]) throws { events.append(contentsOf: newEvents) }
    func update(_ event: CalendarEvent) throws { try update(event, scope: .thisEvent) }
    func delete(id: UUID) throws { try delete(id: id, scope: .thisEvent) }

    func update(_ event: CalendarEvent, scope: RecurrenceScope) throws {
        updatedScopes.append(scope)
        if let index = events.firstIndex(where: { $0.id == event.id }) { events[index] = event }
    }

    func delete(id: UUID, scope: RecurrenceScope) throws {
        deletedScopes.append(scope)
        events.removeAll { $0.id == id }
    }

    func occurrenceIDs(sameSeriesAs id: UUID, scope: RecurrenceScope) -> [UUID] {
        guard scope != .thisEvent, let event = events.first(where: { $0.id == id }) else { return [id] }
        return events.filter { $0.title == event.title && (scope == .allEvents || $0.day >= event.day) }.map(\.id)
    }
}
