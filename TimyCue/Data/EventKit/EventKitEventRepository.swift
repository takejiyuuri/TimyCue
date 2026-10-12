import CoreGraphics
import EventKit
import Foundation

/// Apple カレンダー（EventKit）を保存先にする版（仕様 §68）。
/// TimyCue で作成・編集・削除した予定を Apple カレンダーに反映し、Apple カレンダー側の変更も読み込む。
/// TimyCue だけの情報（到着目標など）は EventKit の予定に入れず、別に保存する（§68・§84）。
/// 読み込む期間は決めず、表示に必要な範囲をそのつど読む（Q35）。読み込むカレンダーは設定で選べる（Q33）。
///
/// Apple カレンダーからの読み込みは時間がかかるので、画面の処理（メインスレッド）では行わない。
/// 裏で読み、読み終わったら onLoaded で知らせる（画面の処理で読むと、予定の多い人で画面が固まり、iOS に止められた）
final class EventKitEventRepository: EventRepository {
    private let store: EKEventStore
    private let linksFile: JSONFile<EventKitLinks>
    private var links: EventKitLinks
    /// links.keys の逆引き（Apple カレンダーの予定の鍵 → TimyCue の予定の id）
    private var idByKey: [String: UUID]
    private let metadata: EventMetadataRepository
    private let preferences: () -> CalendarPreferences
    private let calendar = Calendar.timyCue

    /// 読み込みを頼んだ範囲（内部のキャッシュ。ユーザーから見える制限ではない。Q35）
    private var requestedRange: ClosedRange<CalendarDay>?
    private var cache: [CalendarEvent] = []
    /// 裏で読むための列。順に処理するので、結果も頼んだ順に届く
    private let fetchQueue = DispatchQueue(label: "io.github.takejiyuuri.timycue.eventkit", qos: .userInitiated)

    /// 裏での読み込みが済んで、予定が変わったとき（画面の処理の中で呼ぶ）
    var onLoaded: (@MainActor () -> Void)?

    init(store: EKEventStore,
         metadata: EventMetadataRepository,
         preferences: @escaping () -> CalendarPreferences,
         linksFile: JSONFile<EventKitLinks> = JSONFile(url: JSONFile<EventKitLinks>.appSupportURL(named: "eventkit-links.json"), empty: EventKitLinks())) {
        self.store = store
        self.metadata = metadata
        self.preferences = preferences
        self.linksFile = linksFile
        let loaded = linksFile.load()
        links = loaded
        idByKey = Dictionary(loaded.keys.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
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

    /// その期間の予定がまだなら、足りない部分だけを裏で読む。読み終わったら onLoaded
    func ensureLoaded(from start: CalendarDay, to end: CalendarDay) {
        let wanted = min(start, end)...max(start, end)
        let missing = EventKitMapping.missingRanges(wanted: wanted, requested: requestedRange)
        guard !missing.isEmpty else { return }
        requestedRange = requestedRange.map { min($0.lowerBound, wanted.lowerBound)...max($0.upperBound, wanted.upperBound) } ?? wanted
        load(missing, replacingAll: false)
    }

    /// Apple カレンダー側が変わったとき・読み込むカレンダーを変えたときに、頼んだ範囲を裏で読み直す
    func reloadCache() {
        guard let range = requestedRange else { cache = []; return }
        load([range], replacingAll: true)
    }

    /// 裏で読み、読み終わったら画面の処理の中で取り込む
    private func load(_ ranges: [ClosedRange<CalendarDay>], replacingAll: Bool) {
        let hidden = preferences().hiddenCalendarIDs
        let store = store
        let calendar = calendar
        fetchQueue.async { [weak self] in
            let fetched = ranges.flatMap { Self.fetch(store: store, hiddenCalendarIDs: hidden, range: $0, calendar: calendar) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.merge(fetched, ranges: ranges, replacingAll: replacingAll)
                    self.onLoaded?()
                }
            }
        }
    }

    /// 書き込んだ直後に、その日だけをすぐ読み直す（1 日ぶんなので短い。保存した予定をすぐ画面に出すため）
    private func refreshNow(days: [CalendarDay]) {
        let ranges = Set(days).map { $0...$0 }
        guard !ranges.isEmpty else { return }
        let hidden = preferences().hiddenCalendarIDs
        let fetched = ranges.flatMap { Self.fetch(store: store, hiddenCalendarIDs: hidden, range: $0, calendar: calendar) }
        merge(fetched, ranges: ranges, replacingAll: false)
    }

    /// 裏で読んだ予定を取り込む。TimyCue の予定の id を結び付け、初めて見る予定には色の初期候補を付ける
    private func merge(_ fetched: [FetchedEvent], ranges: [ClosedRange<CalendarDay>], replacingAll: Bool) {
        let known = metadata.allMetadata()
        var newMetadata: [UUID: TimyCueEventMetadata] = [:]
        var linksChanged = false
        var events: [CalendarEvent] = []
        for item in fetched {
            let id: UUID
            if let existing = idByKey[item.key] {
                id = existing
            } else {
                id = UUID()
                links.keys[id] = item.key
                idByKey[item.key] = id
                linksChanged = true
            }
            // 初めて見る Apple カレンダーの予定は、元のカレンダーの色を初期候補にする（§53）
            if known[id] == nil && newMetadata[id] == nil {
                var info = TimyCueEventMetadata()
                info.color = item.calendarColor
                newMetadata[id] = info
            }
            var event = EventKitMapping.calendarEvent(from: item.record,
                                                      id: id,
                                                      endIsUnset: links.endUnset.contains(id),
                                                      source: .appleCalendar,
                                                      calendar: calendar)
            event.calendarID = item.calendarID
            events.append(event)
        }
        if linksChanged { try? linksFile.save(links) }
        // 何百件あっても、ファイルへは 1 回だけ書く
        if !newMetadata.isEmpty { try? metadata.saveAll(newMetadata) }

        var merged = replacingAll ? [] : cache.filter { event in !ranges.contains { $0.contains(event.day) } }
        merged.append(contentsOf: events)
        // 何日にもまたがる予定などが二重に入らないようにする
        var seen = Set<UUID>()
        cache = merged.filter { seen.insert($0.id).inserted }
    }

    /// Apple カレンダーから読んだ予定 1 件（裏で読むので、EKEvent ではなく値だけを持ち出す）
    private struct FetchedEvent {
        let key: String
        let record: ExternalEventRecord
        let calendarID: String?
        let calendarColor: EventColor
    }

    /// 裏で行う読み込みそのもの。EventKit の検索は 4 年までなので区切って読み、同じ予定は 1 件にする
    private static func fetch(store: EKEventStore,
                              hiddenCalendarIDs: Set<String>,
                              range: ClosedRange<CalendarDay>,
                              calendar: Calendar) -> [FetchedEvent] {
        let shown = store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !shown.isEmpty else { return [] }
        var result: [FetchedEvent] = []
        var seenKeys = Set<String>()
        var chunkStart = range.lowerBound
        while chunkStart <= range.upperBound {
            let chunkEnd = min(chunkStart.adding(days: 365 * 3, calendar: calendar), range.upperBound)
            let predicate = store.predicateForEvents(withStart: chunkStart.date(calendar: calendar),
                                                     end: chunkEnd.adding(days: 1, calendar: calendar).date(calendar: calendar),
                                                     calendars: shown)
            for ekEvent in store.events(matching: predicate) {
                let key = linkKey(for: ekEvent)
                guard seenKeys.insert(key).inserted else { continue }
                result.append(FetchedEvent(key: key,
                                           record: record(of: ekEvent),
                                           calendarID: ekEvent.calendar?.calendarIdentifier,
                                           calendarColor: nearestColor(of: ekEvent.calendar)))
            }
            chunkStart = chunkEnd.adding(days: 1, calendar: calendar)
        }
        return result
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
            setKey(Self.linkKey(for: ekEvent), for: event.id)
            setEndUnset(event)
        }
        try store.commit()
        try linksFile.save(links)
        refreshNow(days: events.map(\.day))
    }

    func update(_ event: CalendarEvent) throws {
        guard let ekEvent = find(event.id) else { throw EventRepositoryError.notFound(event.id) }
        Self.apply(EventKitMapping.record(from: event, calendar: calendar), to: ekEvent)
        // その予定だけ保存先を変えた（Q32）
        if let calendarID = event.calendarID, calendarID != ekEvent.calendar?.calendarIdentifier,
           let target = store.calendar(withIdentifier: calendarID), target.allowsContentModifications {
            ekEvent.calendar = target
        }
        let oldDay = cache.first { $0.id == event.id }?.day
        try store.save(ekEvent, span: .thisEvent, commit: true)
        // 日時を変えると、繰り返しの回の鍵が変わることがある
        setKey(Self.linkKey(for: ekEvent), for: event.id)
        setEndUnset(event)
        try linksFile.save(links)
        refreshNow(days: [event.day] + (oldDay.map { [$0] } ?? []))
    }

    func delete(id: UUID) throws {
        guard let ekEvent = find(id) else { throw EventRepositoryError.notFound(id) }
        // 繰り返しの予定の「これ以降」「すべて」（§64）は、繰り返しを作る段階で選べるようにする。今はこの回だけ
        try store.remove(ekEvent, span: .thisEvent, commit: true)
        setKey(nil, for: id)
        links.endUnset.remove(id)
        try linksFile.save(links)
        cache.removeAll { $0.id == id }
    }

    // MARK: - 内部

    /// 予定の id と Apple カレンダーの予定の鍵を結ぶ（逆引きもそろえる）
    private func setKey(_ key: String?, for id: UUID) {
        if let old = links.keys[id], idByKey[old] == id { idByKey[old] = nil }
        links.keys[id] = key
        if let key { idByKey[key] = id }
    }

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
