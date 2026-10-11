import CoreGraphics
import EventKit
import Foundation

/// Apple カレンダー（EventKit）を保存先にする版（仕様 §68）。
/// TimyCue で作成・編集・削除した予定を Apple カレンダーに反映し、Apple カレンダー側の変更も読み込む。
/// TimyCue だけの情報（到着目標など）は EventKit の予定に入れず、別に保存する（§68・§84）。
/// 読み込む期間は決めず、表示に必要な範囲をそのつど読む（Q35）。読み込むカレンダーは設定で選べる（Q33）
final class EventKitEventRepository: EventRepository {
    private let store: EKEventStore
    private let linksFile: JSONFile<EventKitLinks>
    private var links: EventKitLinks
    private let metadata: EventMetadataRepository
    private let preferences: () -> CalendarPreferences
    private let calendar = Calendar.timyCue

    /// 読み込み済みの範囲（内部のキャッシュ。ユーザーから見える制限ではない。Q35）
    private var loadedRange: ClosedRange<CalendarDay>?
    private var cache: [CalendarEvent] = []
    /// 一度に読む範囲の最低の長さ（日。EventKit の検索は 4 年まで）
    static let minimumChunkDays = 60

    init(store: EKEventStore,
         metadata: EventMetadataRepository,
         preferences: @escaping () -> CalendarPreferences,
         linksFile: JSONFile<EventKitLinks> = JSONFile(url: JSONFile<EventKitLinks>.appSupportURL(named: "eventkit-links.json"), empty: EventKitLinks())) {
        self.store = store
        self.metadata = metadata
        self.preferences = preferences
        self.linksFile = linksFile
        links = linksFile.load()
    }

    // MARK: - カレンダー

    /// 見えるカレンダー（iCloud・Google・Exchange なども。Q33）
    func calendars() -> [CalendarChoice] {
        store.calendars(for: .event).map { ekCalendar in
            CalendarChoice(id: ekCalendar.calendarIdentifier,
                           title: ekCalendar.title,
                           sourceTitle: ekCalendar.source?.title ?? "",
                           isWritable: ekCalendar.allowsContentModifications,
                           color: Self.nearestColor(of: ekCalendar))
        }
    }

    /// iPhone の「新規イベントのデフォルトカレンダー」（Q32）
    var systemDefaultCalendarID: String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    // MARK: - 読み込み

    func allEvents() -> [CalendarEvent] {
        cache
    }

    func ensureLoaded(from start: CalendarDay, to end: CalendarDay) {
        let wanted = min(start, end)...max(start, end)
        if let loaded = loadedRange, loaded.contains(wanted.lowerBound), loaded.contains(wanted.upperBound) { return }
        let merged = loadedRange.map { min($0.lowerBound, wanted.lowerBound)...max($0.upperBound, wanted.upperBound) } ?? wanted
        loadedRange = merged
        reloadCache()
    }

    /// Apple カレンダー側が変わったときなど、読み込み済みの範囲を読み直す
    func reloadCache() {
        guard let range = loadedRange else { cache = []; return }
        let known = metadata.allMetadata()
        let shown = store.calendars(for: .event).filter { preferences().isShown($0.calendarIdentifier) }
        guard !shown.isEmpty else { cache = []; return }
        var linksChanged = false
        var result: [CalendarEvent] = []

        // EventKit の検索は 4 年までなので、区切って読む
        var chunkStart = range.lowerBound
        while chunkStart <= range.upperBound {
            let chunkEnd = min(chunkStart.adding(days: 365 * 3, calendar: calendar), range.upperBound)
            let predicate = store.predicateForEvents(withStart: chunkStart.date(calendar: calendar),
                                                     end: chunkEnd.adding(days: 1, calendar: calendar).date(calendar: calendar),
                                                     calendars: shown)
            for ekEvent in store.events(matching: predicate) {
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
                var event = EventKitMapping.calendarEvent(from: Self.record(of: ekEvent),
                                                          id: id,
                                                          endIsUnset: links.endUnset.contains(id),
                                                          source: .appleCalendar,
                                                          calendar: calendar)
                event.calendarID = ekEvent.calendar?.calendarIdentifier
                result.append(event)
            }
            chunkStart = chunkEnd.adding(days: 1, calendar: calendar)
        }
        if linksChanged { try? linksFile.save(links) }
        cache = result
    }

    // MARK: - 書き込み

    func insert(_ events: [CalendarEvent]) throws {
        let writable = calendars().filter(\.isWritable)
        for event in events {
            guard let targetID = CalendarPreferences.saveTarget(eventCalendarID: event.calendarID,
                                                                preferences: preferences(),
                                                                systemDefaultID: systemDefaultCalendarID,
                                                                writable: writable),
                  let target = store.calendar(withIdentifier: targetID) else {
                throw EventKitRepositoryError.noCalendar
            }
            let ekEvent = EKEvent(eventStore: store)
            ekEvent.calendar = target
            Self.apply(EventKitMapping.record(from: event, calendar: calendar), to: ekEvent)
            try store.save(ekEvent, span: .thisEvent, commit: false)
            links.keys[event.id] = Self.linkKey(for: ekEvent)
            setEndUnset(event)
        }
        try store.commit()
        try linksFile.save(links)
        reloadCache()
    }

    func update(_ event: CalendarEvent) throws {
        guard let ekEvent = find(event.id) else { throw EventRepositoryError.notFound(event.id) }
        Self.apply(EventKitMapping.record(from: event, calendar: calendar), to: ekEvent)
        // その予定だけ保存先を変えた（Q32）
        if let calendarID = event.calendarID, calendarID != ekEvent.calendar?.calendarIdentifier,
           let target = store.calendar(withIdentifier: calendarID), target.allowsContentModifications {
            ekEvent.calendar = target
        }
        try store.save(ekEvent, span: .thisEvent, commit: true)
        // 日時を変えると、繰り返しの回の鍵が変わることがある
        links.keys[event.id] = Self.linkKey(for: ekEvent)
        setEndUnset(event)
        try linksFile.save(links)
        reloadCache()
    }

    func delete(id: UUID) throws {
        guard let ekEvent = find(id) else { throw EventRepositoryError.notFound(id) }
        // 繰り返しの予定の「これ以降」「すべて」（§64）は、繰り返しを作る段階で選べるようにする。今はこの回だけ
        try store.remove(ekEvent, span: .thisEvent, commit: true)
        links.keys[id] = nil
        links.endUnset.remove(id)
        try linksFile.save(links)
        reloadCache()
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
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rgb = color.converted(to: space, intent: .defaultIntent, options: nil),
              let components = rgb.components, components.count >= 3 else { return .orange }
        return EventColor.nearest(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

enum EventKitRepositoryError: Error {
    /// 新しい予定を入れる Apple カレンダーがない
    case noCalendar
}
