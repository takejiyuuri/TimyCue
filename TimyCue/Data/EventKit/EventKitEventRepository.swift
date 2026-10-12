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
        // 繰り返しのまだ見ていない回は、同じ繰り返しのほかの回の TimyCue の情報（到着目標など）を引き継ぐ
        var seriesMetadata: [String: TimyCueEventMetadata] = [:]
        for (id, key) in links.keys {
            if let info = known[id] { seriesMetadata[EventKitMapping.parseLinkKey(key).itemIdentifier] = info }
        }
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
                if let series = seriesMetadata[EventKitMapping.parseLinkKey(item.key).itemIdentifier] {
                    newMetadata[id] = series
                } else {
                    var info = TimyCueEventMetadata()
                    info.color = item.calendarColor
                    newMetadata[id] = info
                }
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
                                           record: record(of: ekEvent, store: store),
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
            Self.apply(EventKitMapping.record(from: event, calendar: calendar), to: ekEvent, includeRecurrence: true)
            try store.save(ekEvent, span: event.repeatRule.isRepeating ? .futureEvents : .thisEvent, commit: false)
            setKey(Self.linkKey(for: ekEvent), for: event.id)
            setEndUnset(event)
        }
        try store.commit()
        try linksFile.save(links)
        refreshNow(days: events.map(\.day))
        // 繰り返しはほかの日にも出るので、読み込んである範囲を読み直す（裏で）
        if events.contains(where: \.repeatRule.isRepeating) { reloadCache() }
    }

    func update(_ event: CalendarEvent) throws {
        try update(event, scope: .thisEvent)
    }

    /// 予定を直す。繰り返し予定は、この予定のみ／これ以降／すべて の範囲で直す（Q44）。
    /// 「この予定のみ」では繰り返しの決まりは変えない。「すべて」は、系列の初めの回に、この回で動かした分だけ同じように当てる
    func update(_ event: CalendarEvent, scope: RecurrenceScope) throws {
        guard let occurrence = find(event.id) else { throw EventRepositoryError.notFound(event.id) }
        let record = EventKitMapping.record(from: event, calendar: calendar)
        let oldDay = cache.first { $0.id == event.id }?.day
        let wasRecurring = occurrence.hasRecurrenceRules

        if !wasRecurring || scope == .thisEvent {
            // 繰り返しでない予定に繰り返しを付けるのもここ（範囲は聞かない）
            Self.apply(record, to: occurrence, includeRecurrence: !wasRecurring)
            moveCalendarIfNeeded(occurrence, to: event.calendarID)
            try store.save(occurrence, span: wasRecurring ? .thisEvent : .futureEvents, commit: true)
            setKey(Self.linkKey(for: occurrence), for: event.id)
        } else {
            let target: EKEvent
            let occurrenceDate: Date
            if scope == .allEvents,
               let master = store.calendarItem(withIdentifier: occurrence.calendarItemIdentifier) as? EKEvent {
                let shift = record.startDate.timeIntervalSince(occurrence.startDate)
                var shifted = record
                shifted.startDate = master.startDate.addingTimeInterval(shift)
                shifted.endDate = shifted.startDate.addingTimeInterval(record.endDate.timeIntervalSince(record.startDate))
                Self.apply(shifted, to: master, includeRecurrence: true)
                target = master
                occurrenceDate = occurrence.occurrenceDate.addingTimeInterval(shift)
            } else {
                Self.apply(record, to: occurrence, includeRecurrence: true)
                target = occurrence
                occurrenceDate = record.startDate
            }
            moveCalendarIfNeeded(target, to: event.calendarID)
            try store.save(target, span: .futureEvents, commit: true)
            setKey(EventKitMapping.linkKey(itemIdentifier: target.calendarItemIdentifier,
                                           occurrenceDate: target.hasRecurrenceRules ? occurrenceDate : nil),
                   for: event.id)
        }
        setEndUnset(event)
        try linksFile.save(links)
        refreshNow(days: [event.day] + (oldDay.map { [$0] } ?? []))
        // 繰り返しが変わると、ほかの日の回も変わるので、読み込んである範囲を読み直す（裏で）
        if (wasRecurring && scope != .thisEvent) || (!wasRecurring && record.repeatRule.isRepeating) {
            reloadCache()
        }
    }

    func delete(id: UUID) throws {
        try delete(id: id, scope: .thisEvent)
    }

    /// 予定を消す。繰り返し予定は、この予定のみ／これ以降／すべて の範囲で消す（§64・Q44）
    func delete(id: UUID, scope: RecurrenceScope) throws {
        guard let occurrence = find(id) else { throw EventRepositoryError.notFound(id) }
        let wasRecurring = occurrence.hasRecurrenceRules
        let removed = occurrenceIDs(sameSeriesAs: id, scope: wasRecurring ? scope : .thisEvent)
        switch (wasRecurring, scope) {
        case (true, .futureEvents):
            try store.remove(occurrence, span: .futureEvents, commit: true)
        case (true, .allEvents):
            let master = (store.calendarItem(withIdentifier: occurrence.calendarItemIdentifier) as? EKEvent) ?? occurrence
            try store.remove(master, span: .futureEvents, commit: true)
        default:
            try store.remove(occurrence, span: .thisEvent, commit: true)
        }
        for removedID in removed {
            setKey(nil, for: removedID)
            links.endUnset.remove(removedID)
        }
        try linksFile.save(links)
        cache.removeAll { removed.contains($0.id) }
    }

    /// 同じ繰り返しの、読み込んである回の id（「これ以降」ならその回から後、「すべて」なら全部。その予定自身も含む）
    func occurrenceIDs(sameSeriesAs id: UUID, scope: RecurrenceScope) -> [UUID] {
        guard scope != .thisEvent, let key = links.keys[id] else { return [id] }
        let item = EventKitMapping.parseLinkKey(key).itemIdentifier
        let day = cache.first { $0.id == id }?.day
        let ids = cache.filter { other in
            guard let otherKey = links.keys[other.id],
                  EventKitMapping.parseLinkKey(otherKey).itemIdentifier == item else { return false }
            if scope == .futureEvents, let day { return other.day >= day }
            return true
        }.map(\.id)
        return ids.contains(id) ? ids : [id] + ids
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

    /// その予定だけ保存先を変えた（Q32）
    private func moveCalendarIfNeeded(_ ekEvent: EKEvent, to calendarID: String?) {
        if let calendarID, calendarID != ekEvent.calendar?.calendarIdentifier,
           let target = store.calendar(withIdentifier: calendarID), target.allowsContentModifications {
            ekEvent.calendar = target
        }
    }

    private static func record(of ekEvent: EKEvent, store: EKEventStore) -> ExternalEventRecord {
        var rule = ekEvent.recurrenceRules?.first
        // 1 回だけ直した回は、繰り返しの決まりを持たないことがあるので、系列のほうから読む
        if rule == nil, ekEvent.hasRecurrenceRules {
            rule = (store.calendarItem(withIdentifier: ekEvent.calendarItemIdentifier) as? EKEvent)?.recurrenceRules?.first
        }
        return ExternalEventRecord(title: ekEvent.title ?? "",
                                   location: ekEvent.location,
                                   startDate: ekEvent.startDate,
                                   endDate: ekEvent.endDate,
                                   isAllDay: ekEvent.isAllDay,
                                   notes: ekEvent.notes,
                                   repeatRule: EventKitRecurrence.repeatRule(from: rule))
    }

    /// includeRecurrence：繰り返しの決まりも書き換えるか（「この予定のみ」のときは書き換えない）
    private static func apply(_ record: ExternalEventRecord, to ekEvent: EKEvent, includeRecurrence: Bool) {
        ekEvent.title = record.title
        ekEvent.location = record.location
        ekEvent.startDate = record.startDate
        ekEvent.endDate = record.endDate
        ekEvent.isAllDay = record.isAllDay
        // メモは主な入力欄に出さないが、Apple カレンダーにあるものは消さない（§55）
        if let notes = record.notes { ekEvent.notes = notes }
        if includeRecurrence {
            ekEvent.recurrenceRules = EventKitRecurrence.rule(from: record.repeatRule).map { [$0] }
        }
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
