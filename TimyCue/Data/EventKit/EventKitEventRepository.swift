import CoreGraphics
import EventKit
import Foundation

/// Apple カレンダー（EventKit）を保存先にする版（仕様 §68）。
/// TimyCue で作成・編集・削除した予定を Apple カレンダーに反映し、Apple カレンダー側の変更も読み込む。
/// TimyCue だけの情報（到着目標など）は EventKit の予定に入れず、別に保存する（§68・§84）
final class EventKitEventRepository: EventRepository {
    private let store: EKEventStore
    private let linksFile: JSONFile<EventKitLinks>
    private var links: EventKitLinks
    private let metadata: EventMetadataRepository
    private let calendar = Calendar.timyCue

    /// 読み込む範囲（今日から前 1 年・後 2 年。仮。EventKit の検索は 4 年まで）
    static let monthsBefore = 12
    static let monthsAfter = 24

    init(store: EKEventStore,
         metadata: EventMetadataRepository,
         linksFile: JSONFile<EventKitLinks> = JSONFile(url: JSONFile<EventKitLinks>.appSupportURL(named: "eventkit-links.json"), empty: EventKitLinks())) {
        self.store = store
        self.metadata = metadata
        self.linksFile = linksFile
        links = linksFile.load()
    }

    func allEvents() -> [CalendarEvent] {
        let now = Date()
        guard let start = calendar.date(byAdding: .month, value: -Self.monthsBefore, to: now),
              let end = calendar.date(byAdding: .month, value: Self.monthsAfter, to: now) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let known = metadata.allMetadata()
        var linksChanged = false

        let events = store.events(matching: predicate).map { ekEvent -> CalendarEvent in
            let key = Self.linkKey(for: ekEvent)
            let id: UUID
            if let existing = links.id(forKey: key) {
                id = existing
            } else {
                id = UUID()
                links.keys[id] = key
                linksChanged = true
            }
            // 初めて見る Apple カレンダーの予定は、元のカレンダーの色を初期候補にする（§53）
            if known[id] == nil {
                var info = TimyCueEventMetadata()
                info.color = Self.nearestColor(of: ekEvent.calendar)
                try? metadata.save(info, for: id)
            }
            return EventKitMapping.calendarEvent(from: Self.record(of: ekEvent),
                                                 id: id,
                                                 endIsUnset: links.endUnset.contains(id),
                                                 source: .appleCalendar,
                                                 calendar: calendar)
        }
        if linksChanged { try? linksFile.save(links) }
        return events
    }

    func insert(_ events: [CalendarEvent]) throws {
        guard let target = store.defaultCalendarForNewEvents else { throw EventKitRepositoryError.noCalendar }
        for event in events {
            let ekEvent = EKEvent(eventStore: store)
            ekEvent.calendar = target
            Self.apply(EventKitMapping.record(from: event, calendar: calendar), to: ekEvent)
            try store.save(ekEvent, span: .thisEvent, commit: false)
            links.keys[event.id] = Self.linkKey(for: ekEvent)
            setEndUnset(event)
        }
        try store.commit()
        try linksFile.save(links)
    }

    func update(_ event: CalendarEvent) throws {
        guard let ekEvent = find(event.id) else { throw EventRepositoryError.notFound(event.id) }
        Self.apply(EventKitMapping.record(from: event, calendar: calendar), to: ekEvent)
        try store.save(ekEvent, span: .thisEvent, commit: true)
        // 日時を変えると、繰り返しの回の鍵が変わることがある
        links.keys[event.id] = Self.linkKey(for: ekEvent)
        setEndUnset(event)
        try linksFile.save(links)
    }

    func delete(id: UUID) throws {
        guard let ekEvent = find(id) else { throw EventRepositoryError.notFound(id) }
        // 繰り返しの予定の「これ以降」「すべて」（§64）は、繰り返しを作る段階で選べるようにする。今はこの回だけ
        try store.remove(ekEvent, span: .thisEvent, commit: true)
        links.keys[id] = nil
        links.endUnset.remove(id)
        try linksFile.save(links)
    }

    // MARK: - 内部

    private func setEndUnset(_ event: CalendarEvent) {
        if event.durationMinutes == nil && !event.isAllDay {
            links.endUnset.insert(event.id)
        } else {
            links.endUnset.remove(event.id)
        }
    }

    private func find(_ id: UUID) -> EKEvent? {
        guard let key = links.keys[id] else { return nil }
        let parsed = EventKitMapping.parseLinkKey(key)
        guard let occurrence = parsed.occurrenceDate else {
            return store.calendarItem(withIdentifier: parsed.itemIdentifier) as? EKEvent
        }
        // 繰り返しの予定は、その回の日の予定から探す
        let dayStart = calendar.startOfDay(for: occurrence)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        return store.events(matching: predicate).first {
            $0.calendarItemIdentifier == parsed.itemIdentifier && $0.occurrenceDate == occurrence
        }
    }

    private static func linkKey(for ekEvent: EKEvent) -> String {
        EventKitMapping.linkKey(itemIdentifier: ekEvent.calendarItemIdentifier,
                                occurrenceDate: ekEvent.hasRecurrenceRules ? ekEvent.occurrenceDate : nil)
    }

    private static func record(of ekEvent: EKEvent) -> ExternalEventRecord {
        ExternalEventRecord(title: ekEvent.title ?? "",
                            location: ekEvent.location,
                            startDate: ekEvent.startDate,
                            endDate: ekEvent.endDate,
                            isAllDay: ekEvent.isAllDay,
                            notes: ekEvent.notes)
    }

    private static func apply(_ record: ExternalEventRecord, to ekEvent: EKEvent) {
        ekEvent.title = record.title
        ekEvent.location = record.location
        ekEvent.startDate = record.startDate
        ekEvent.endDate = record.endDate
        ekEvent.isAllDay = record.isAllDay
        // メモは主な入力欄に出さないが、Apple カレンダーにあるものは消さない（§55）
        if let notes = record.notes { ekEvent.notes = notes }
    }

    private static func nearestColor(of ekCalendar: EKCalendar?) -> EventColor {
        guard let color = ekCalendar?.cgColor,
              let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let components = rgb.components, components.count >= 3 else { return .orange }
        return EventColor.nearest(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

enum EventKitRepositoryError: Error {
    /// 新しい予定を入れる Apple カレンダーがない
    case noCalendar
}
